#!/bin/bash
# AWK Transformer Forward Pass Wrapper
# Because AWK deserves a nice bash jacket to wear

_AWK_FORWARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AWK_SCRIPT="$_AWK_FORWARD_DIR/transformer.awk"

# Source math.sh for fp_softmax, fp_argmax, fp_sample used in generation
source "$_AWK_FORWARD_DIR/math.sh"

# Global model config (defaults, overwritten by init_model)
declare -g N_EMBD=64
declare -g N_HEAD=4
declare -g N_LAYER=3
declare -g VOCAB_SIZE=256
declare -g BLOCK_SIZE=64
declare -g HEAD_DIM=16  # N_EMBD / N_HEAD

# Load model configuration only (AWK loads weights itself)
init_model() {
    MODEL_DIR="$1"

    echo "Loading model config from $MODEL_DIR..." >&2

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
    echo "Model ready (AWK-powered)!" >&2
    return 0
}

# Forward pass via AWK
# Input: token IDs (space-separated)
# Returns: logits for next token [vocab_size]
forward() {
    local tokens="$1"

    # Call AWK transformer
    awk -f "$_AWK_SCRIPT" -v model_dir="$MODEL_DIR" -v tokens="$tokens"
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
    echo "Using AWK-powered inference (fancy!)" >&2

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
    echo "=== AWK Transformer Wrapper Test ==="
    echo
    echo "Usage:"
    echo "  source awk_forward.sh"
    echo "  init_model /path/to/model"
    echo "  generate 'prompt' num_tokens"
    echo
    echo "Or run directly:"
    echo "  ./awk_forward.sh test /path/to/model 'Hello'"
    echo

    if [[ "$1" == "test" ]]; then
        MODEL_DIR="${2:-model}"
        TEST_PROMPT="${3:-Hello}"

        init_model "$MODEL_DIR" || exit 1

        echo "Testing forward pass..."
        tokens=""
        for ((i=0; i<${#TEST_PROMPT}; i++)); do
            char="${TEST_PROMPT:i:1}"
            tokens="$tokens $(printf '%d' "'$char")"
        done
        tokens="${tokens# }"

        echo "Tokens: $tokens"
        echo "Running forward pass..."

        logits=$(forward "$tokens")
        echo "Output: $logits"
        echo
        echo "First 10 logits:"
        echo "$logits" | tr ' ' '\n' | head -10
    fi
fi
