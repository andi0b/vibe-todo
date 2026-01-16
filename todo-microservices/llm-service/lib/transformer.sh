#!/bin/bash
# Transformer Components Library for Bash LLM
# Attention is all you need. And bash. Mostly bash.

_TRANSFORMER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_TRANSFORMER_LIB_DIR/matrix.sh"

# Global model state (loaded weights)
# Note: MODEL_DIR is set by the calling script, don't override it here
declare -g N_EMBD=64
declare -g N_HEAD=2
declare -g N_LAYER=2
declare -g VOCAB_SIZE=256
declare -g BLOCK_SIZE=64
declare -g HEAD_DIM=32  # N_EMBD / N_HEAD

# Weight arrays (loaded on model init)
declare -ga WTE=()      # Token embeddings [vocab_size, n_embd]
declare -ga WPE=()      # Position embeddings [block_size, n_embd]
declare -ga LN_F_W=()   # Final layer norm weight
declare -ga LN_F_B=()   # Final layer norm bias

# Per-layer weights (indexed by layer number)
# We'll use associative arrays for flexibility
declare -gA LAYER_WEIGHTS=()

# Load model configuration
load_config() {
    local config_file="$MODEL_DIR/config.txt"
    [[ ! -f "$config_file" ]] && { echo "ERROR: config.txt not found" >&2; return 1; }

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        case "$key" in
            n_embd)     N_EMBD=$value ;;
            n_head)     N_HEAD=$value ;;
            n_layer)    N_LAYER=$value ;;
            vocab_size) VOCAB_SIZE=$value ;;
            block_size) BLOCK_SIZE=$value ;;
        esac
    done < "$config_file"

    HEAD_DIM=$((N_EMBD / N_HEAD))
    echo "Config: n_embd=$N_EMBD, n_head=$N_HEAD, n_layer=$N_LAYER, vocab=$VOCAB_SIZE, ctx=$BLOCK_SIZE" >&2
}

# Load weights from file into array
# Returns space-separated values
load_weights() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "ERROR: $file not found" >&2; return 1; }

    local -a weights=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && weights+=("$line")
    done < "$file"

    echo "${weights[*]}"
}

# Initialize model (load all weights)
init_model() {
    MODEL_DIR="$1"

    echo "Loading model from $MODEL_DIR..." >&2

    load_config || return 1

    # Token embeddings
    echo "  Loading token embeddings..." >&2
    WTE=($(load_weights "$MODEL_DIR/wte.txt"))
    echo "    Loaded ${#WTE[@]} values (expect $((VOCAB_SIZE * N_EMBD)))" >&2

    # Position embeddings
    echo "  Loading position embeddings..." >&2
    WPE=($(load_weights "$MODEL_DIR/wpe.txt"))
    echo "    Loaded ${#WPE[@]} values (expect $((BLOCK_SIZE * N_EMBD)))" >&2

    # Final layer norm
    echo "  Loading final layer norm..." >&2
    LN_F_W=($(load_weights "$MODEL_DIR/ln_f_weight.txt"))
    LN_F_B=($(load_weights "$MODEL_DIR/ln_f_bias.txt"))

    # Per-layer weights
    for ((layer=0; layer<N_LAYER; layer++)); do
        echo "  Loading layer $layer..." >&2
        local prefix="$MODEL_DIR/blocks/$layer"

        # Attention layer norm
        LAYER_WEIGHTS["${layer}_ln1_w"]=$(load_weights "$prefix/ln1_weight.txt")
        LAYER_WEIGHTS["${layer}_ln1_b"]=$(load_weights "$prefix/ln1_bias.txt")

        # Attention weights (Q, K, V combined into one matrix for efficiency)
        # c_attn projects to 3*n_embd (Q, K, V concatenated)
        LAYER_WEIGHTS["${layer}_attn_w"]=$(load_weights "$prefix/attn_weight.txt")
        LAYER_WEIGHTS["${layer}_attn_b"]=$(load_weights "$prefix/attn_bias.txt")

        # Attention output projection
        LAYER_WEIGHTS["${layer}_attn_proj_w"]=$(load_weights "$prefix/attn_proj_weight.txt")
        LAYER_WEIGHTS["${layer}_attn_proj_b"]=$(load_weights "$prefix/attn_proj_bias.txt")

        # FFN layer norm
        LAYER_WEIGHTS["${layer}_ln2_w"]=$(load_weights "$prefix/ln2_weight.txt")
        LAYER_WEIGHTS["${layer}_ln2_b"]=$(load_weights "$prefix/ln2_bias.txt")

        # FFN weights (fc1 expands, fc2 contracts)
        LAYER_WEIGHTS["${layer}_ffn_fc1_w"]=$(load_weights "$prefix/ffn_fc1_weight.txt")
        LAYER_WEIGHTS["${layer}_ffn_fc1_b"]=$(load_weights "$prefix/ffn_fc1_bias.txt")
        LAYER_WEIGHTS["${layer}_ffn_fc2_w"]=$(load_weights "$prefix/ffn_fc2_weight.txt")
        LAYER_WEIGHTS["${layer}_ffn_fc2_b"]=$(load_weights "$prefix/ffn_fc2_bias.txt")
    done

    echo "Model loaded!" >&2
    return 0
}

# Token embedding lookup
# Usage: embed_token 65 -> returns embedding vector for token 65
embed_token() {
    local token_id="$1"
    local start=$((token_id * N_EMBD))
    echo "${WTE[*]:$start:$N_EMBD}"
}

# Position embedding lookup
embed_position() {
    local pos="$1"
    local start=$((pos * N_EMBD))
    echo "${WPE[*]:$start:$N_EMBD}"
}

# Single-head attention (for one head)
# Takes Q, K, V vectors for a single head
# Returns attention output for that head
single_head_attention() {
    local -a Q=($1)      # [seq_len, head_dim]
    local -a K=($2)      # [seq_len, head_dim]
    local -a V=($3)      # [seq_len, head_dim]
    local seq_len="$4"
    local head_dim="$5"
    local is_causal="${6:-1}"

    # Scale factor: 1/sqrt(head_dim)
    local scale_sq=$((head_dim * SCALE))
    local scale=$(fp_sqrt "$scale_sq")

    # Compute attention scores: Q @ K^T
    # For each query position, compute dot product with all key positions
    local -a attn_weights=()

    for ((i=0; i<seq_len; i++)); do
        local q_start=$((i * head_dim))
        local -a q_vec=(${Q[*]:$q_start:$head_dim})

        local -a row_scores=()
        for ((j=0; j<seq_len; j++)); do
            # Causal masking: can only attend to positions <= current
            if [[ $is_causal -eq 1 && $j -gt $i ]]; then
                row_scores+=("-1000000000")  # Large negative = ~0 after softmax
            else
                local k_start=$((j * head_dim))
                local -a k_vec=(${K[*]:$k_start:$head_dim})

                # Dot product
                local score=0
                for ((d=0; d<head_dim; d++)); do
                    score=$(( score + (q_vec[d] * k_vec[d]) / SCALE ))
                done

                # Scale
                score=$(( (score * SCALE) / scale ))
                row_scores+=("$score")
            fi
        done

        # Softmax over this row
        local probs=$(fp_softmax "${row_scores[*]}")
        attn_weights+=($probs)
    done

    # Apply attention to values: attn_weights @ V
    local -a output=()
    for ((i=0; i<seq_len; i++)); do
        local w_start=$((i * seq_len))

        for ((d=0; d<head_dim; d++)); do
            local sum=0
            for ((j=0; j<seq_len; j++)); do
                local w=${attn_weights[$((w_start + j))]}
                local v=${V[$((j * head_dim + d))]}
                sum=$(( sum + (w * v) / SCALE ))
            done
            output+=("$sum")
        done
    done

    echo "${output[*]}"
}

# Multi-head attention
# Input: hidden states [seq_len, n_embd]
# Returns: attention output [seq_len, n_embd]
multi_head_attention() {
    local -a hidden=($1)
    local seq_len="$2"
    local layer="$3"

    # Get weights
    local -a attn_w=(${LAYER_WEIGHTS["${layer}_attn_w"]})
    local -a attn_b=(${LAYER_WEIGHTS["${layer}_attn_b"]})
    local -a proj_w=(${LAYER_WEIGHTS["${layer}_attn_proj_w"]})
    local -a proj_b=(${LAYER_WEIGHTS["${layer}_attn_proj_b"]})

    # Project to Q, K, V (combined in one matrix)
    # attn_w is [n_embd, 3*n_embd], hidden is [seq_len, n_embd]
    local -a qkv=()
    local qkv_dim=$((3 * N_EMBD))

    for ((t=0; t<seq_len; t++)); do
        local h_start=$((t * N_EMBD))
        local -a h_vec=(${hidden[*]:$h_start:$N_EMBD})

        # Multiply by weight matrix and add bias
        for ((i=0; i<qkv_dim; i++)); do
            local sum=${attn_b[$i]}
            for ((j=0; j<N_EMBD; j++)); do
                local w=${attn_w[$((j * qkv_dim + i))]}
                sum=$(( sum + (h_vec[j] * w) / SCALE ))
            done
            qkv+=("$sum")
        done
    done

    # Split into Q, K, V for each head and compute attention
    local -a all_head_outputs=()

    for ((h=0; h<N_HEAD; h++)); do
        local head_offset=$((h * HEAD_DIM))

        # Extract Q, K, V for this head
        local -a Q=() K=() V=()

        for ((t=0; t<seq_len; t++)); do
            local base=$((t * qkv_dim))

            # Q at offset 0, K at offset n_embd, V at offset 2*n_embd
            for ((d=0; d<HEAD_DIM; d++)); do
                Q+=("${qkv[$((base + head_offset + d))]}")
                K+=("${qkv[$((base + N_EMBD + head_offset + d))]}")
                V+=("${qkv[$((base + 2*N_EMBD + head_offset + d))]}")
            done
        done

        # Compute attention for this head
        local head_out=$(single_head_attention "${Q[*]}" "${K[*]}" "${V[*]}" "$seq_len" "$HEAD_DIM" 1)
        all_head_outputs+=($head_out)
    done

    # Concatenate heads: [seq_len, n_head, head_dim] -> [seq_len, n_embd]
    local -a concat=()
    for ((t=0; t<seq_len; t++)); do
        for ((h=0; h<N_HEAD; h++)); do
            local head_base=$((h * seq_len * HEAD_DIM + t * HEAD_DIM))
            for ((d=0; d<HEAD_DIM; d++)); do
                concat+=("${all_head_outputs[$((head_base + d))]}")
            done
        done
    done

    # Output projection
    local -a output=()
    for ((t=0; t<seq_len; t++)); do
        local c_start=$((t * N_EMBD))
        local -a c_vec=(${concat[*]:$c_start:$N_EMBD})

        for ((i=0; i<N_EMBD; i++)); do
            local sum=${proj_b[$i]}
            for ((j=0; j<N_EMBD; j++)); do
                local w=${proj_w[$((j * N_EMBD + i))]}
                sum=$(( sum + (c_vec[j] * w) / SCALE ))
            done
            output+=("$sum")
        done
    done

    echo "${output[*]}"
}

# Feed-forward network
# Input: hidden states [seq_len, n_embd]
# Returns: FFN output [seq_len, n_embd]
feed_forward() {
    local -a hidden=($1)
    local seq_len="$2"
    local layer="$3"

    local -a fc1_w=(${LAYER_WEIGHTS["${layer}_ffn_fc1_w"]})
    local -a fc1_b=(${LAYER_WEIGHTS["${layer}_ffn_fc1_b"]})
    local -a fc2_w=(${LAYER_WEIGHTS["${layer}_ffn_fc2_w"]})
    local -a fc2_b=(${LAYER_WEIGHTS["${layer}_ffn_fc2_b"]})

    local hidden_dim=$((4 * N_EMBD))  # Standard 4x expansion

    local -a output=()

    for ((t=0; t<seq_len; t++)); do
        local h_start=$((t * N_EMBD))
        local -a h_vec=(${hidden[*]:$h_start:$N_EMBD})

        # First linear: n_embd -> 4*n_embd
        local -a intermediate=()
        for ((i=0; i<hidden_dim; i++)); do
            local sum=${fc1_b[$i]}
            for ((j=0; j<N_EMBD; j++)); do
                local w=${fc1_w[$((j * hidden_dim + i))]}
                sum=$(( sum + (h_vec[j] * w) / SCALE ))
            done
            # GELU activation
            intermediate+=("$(fp_gelu "$sum")")
        done

        # Second linear: 4*n_embd -> n_embd
        for ((i=0; i<N_EMBD; i++)); do
            local sum=${fc2_b[$i]}
            for ((j=0; j<hidden_dim; j++)); do
                local w=${fc2_w[$((j * N_EMBD + i))]}
                sum=$(( sum + (intermediate[j] * w) / SCALE ))
            done
            output+=("$sum")
        done
    done

    echo "${output[*]}"
}

# Single transformer block
# Input: hidden states [seq_len, n_embd]
# Returns: block output [seq_len, n_embd]
transformer_block() {
    local -a hidden=($1)
    local seq_len="$2"
    local layer="$3"

    local -a ln1_w=(${LAYER_WEIGHTS["${layer}_ln1_w"]})
    local -a ln1_b=(${LAYER_WEIGHTS["${layer}_ln1_b"]})
    local -a ln2_w=(${LAYER_WEIGHTS["${layer}_ln2_w"]})
    local -a ln2_b=(${LAYER_WEIGHTS["${layer}_ln2_b"]})

    # Pre-norm for attention
    local -a normed1=()
    for ((t=0; t<seq_len; t++)); do
        local h_start=$((t * N_EMBD))
        local h_vec="${hidden[*]:$h_start:$N_EMBD}"
        local n_vec=$(layer_norm "$h_vec" "${ln1_w[*]}" "${ln1_b[*]}")
        normed1+=($n_vec)
    done

    # Multi-head attention
    local attn_out=$(multi_head_attention "${normed1[*]}" "$seq_len" "$layer")
    local -a attn_out_arr=($attn_out)

    # Residual connection
    local -a residual1=()
    for ((i=0; i<${#hidden[@]}; i++)); do
        residual1+=("$((hidden[i] + attn_out_arr[i]))")
    done

    # Pre-norm for FFN
    local -a normed2=()
    for ((t=0; t<seq_len; t++)); do
        local h_start=$((t * N_EMBD))
        local h_vec="${residual1[*]:$h_start:$N_EMBD}"
        local n_vec=$(layer_norm "$h_vec" "${ln2_w[*]}" "${ln2_b[*]}")
        normed2+=($n_vec)
    done

    # Feed-forward
    local ffn_out=$(feed_forward "${normed2[*]}" "$seq_len" "$layer")
    local -a ffn_out_arr=($ffn_out)

    # Residual connection
    local -a output=()
    for ((i=0; i<${#residual1[@]}; i++)); do
        output+=("$((residual1[i] + ffn_out_arr[i]))")
    done

    echo "${output[*]}"
}

# Full forward pass
# Input: token IDs (space-separated)
# Returns: logits for next token [vocab_size]
forward() {
    local -a tokens=($1)
    local seq_len=${#tokens[@]}

    [[ $seq_len -gt $BLOCK_SIZE ]] && seq_len=$BLOCK_SIZE

    echo "Forward pass: $seq_len tokens through $N_LAYER layers..." >&2

    # Token + position embeddings
    local -a hidden=()
    for ((t=0; t<seq_len; t++)); do
        local tok_emb=$(embed_token "${tokens[t]}")
        local pos_emb=$(embed_position "$t")
        local -a tok_arr=($tok_emb)
        local -a pos_arr=($pos_emb)

        for ((i=0; i<N_EMBD; i++)); do
            hidden+=("$((tok_arr[i] + pos_arr[i]))")
        done
    done

    # Transformer blocks
    for ((layer=0; layer<N_LAYER; layer++)); do
        echo "  Layer $layer..." >&2
        hidden=($(transformer_block "${hidden[*]}" "$seq_len" "$layer"))
    done

    # Final layer norm (only on last position for next-token prediction)
    local last_start=$(( (seq_len - 1) * N_EMBD ))
    local last_hidden="${hidden[*]:$last_start:$N_EMBD}"
    local normed=$(layer_norm "$last_hidden" "${LN_F_W[*]}" "${LN_F_B[*]}")
    local -a normed_arr=($normed)

    # Project to vocabulary (using transpose of token embeddings)
    # logits = normed @ wte.T
    local -a logits=()
    for ((v=0; v<VOCAB_SIZE; v++)); do
        local emb_start=$((v * N_EMBD))
        local sum=0
        for ((i=0; i<N_EMBD; i++)); do
            sum=$(( sum + (normed_arr[i] * WTE[emb_start + i]) / SCALE ))
        done
        logits+=("$sum")
    done

    echo "${logits[*]}"
}

# Generate next token
# Returns: token ID
generate_token() {
    local tokens="$1"
    local temperature="${2:-$SCALE}"

    local logits=$(forward "$tokens")

    if [[ $temperature -eq 0 ]]; then
        # Greedy: argmax
        fp_argmax "$logits"
    else
        # Sample with temperature
        # Scale logits by temperature
        local -a scaled=()
        local -a logit_arr=($logits)
        for l in "${logit_arr[@]}"; do
            scaled+=("$(( (l * SCALE) / temperature ))")
        done

        local probs=$(fp_softmax "${scaled[*]}")
        fp_sample "$probs"
    fi
}

# Generate sequence
# Usage: generate "Hello" 20 -> generates 20 new tokens
generate() {
    local prompt="$1"
    local max_tokens="${2:-20}"
    local temperature="${3:-$SCALE}"

    # Convert prompt to token IDs (ASCII values)
    local -a tokens=()
    for ((i=0; i<${#prompt}; i++)); do
        local char="${prompt:i:1}"
        tokens+=("$(printf '%d' "'$char")")
    done

    echo "Generating from: '$prompt' (${#tokens[@]} tokens)..." >&2

    local output="$prompt"

    for ((n=0; n<max_tokens; n++)); do
        echo "  Generating token $((n+1))/$max_tokens..." >&2

        local next_token=$(generate_token "${tokens[*]}" "$temperature")
        tokens+=("$next_token")

        # Convert back to character
        local char
        if [[ $next_token -ge 32 && $next_token -le 126 ]]; then
            char=$(printf "\\$(printf '%03o' "$next_token")")
        else
            char="?"
        fi

        output="${output}${char}"
        echo "    Token $next_token -> '$char'" >&2

        # Truncate if too long
        if [[ ${#tokens[@]} -gt $BLOCK_SIZE ]]; then
            tokens=("${tokens[@]:1}")
        fi
    done

    echo "$output"
}

# Self-test
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== Transformer Library Test ==="
    echo
    echo "This library requires a model to be loaded."
    echo "Use: init_model /path/to/model"
    echo "Then: generate 'prompt' num_tokens"
    echo
fi
