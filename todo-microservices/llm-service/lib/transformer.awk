#!/usr/bin/awk -f
# Transformer Forward Pass in AWK
# Because if we're going to be absurd, let's at least be fast about it
#
# Usage: awk -f transformer.awk -v model_dir=/path/to/model -v tokens="72 101 108 108 111"
#
# The eternal question: "Can AWK run a neural network?"
# The answer: "Should it? No. Will it? Absolutely."

BEGIN {
    # Configuration defaults
    if (!model_dir) model_dir = "model"
    if (!tokens) tokens = "72 101 108 108 111"  # "Hello"

    # Fixed-point scale for compatibility with bash version
    SCALE = 10000

    # Load and run
    load_model()

    # Parse input tokens
    n_tokens = split(tokens, token_arr, " ")

    # Forward pass
    forward(token_arr, n_tokens)

    # Output logits
    for (i = 1; i <= vocab_size; i++) {
        printf "%d", logits[i]
        if (i < vocab_size) printf " "
    }
    printf "\n"
}

#=============================================================================
# MODEL LOADING
#=============================================================================

function load_model(    line, i, j, layer, file, idx) {
    # Load config
    file = model_dir "/config.txt"
    while ((getline line < file) > 0) {
        if (match(line, /^n_embd=([0-9]+)/, m)) n_embd = int(substr(line, 8))
        else if (match(line, /^n_head=/)) n_head = int(substr(line, 8))
        else if (match(line, /^n_layer=/)) n_layer = int(substr(line, 9))
        else if (match(line, /^vocab_size=/)) vocab_size = int(substr(line, 12))
        else if (match(line, /^block_size=/)) block_size = int(substr(line, 12))

        # Parse key=value more robustly
        if (index(line, "=") > 0) {
            key = substr(line, 1, index(line, "=") - 1)
            val = substr(line, index(line, "=") + 1)
            if (key == "n_embd") n_embd = int(val)
            else if (key == "n_head") n_head = int(val)
            else if (key == "n_layer") n_layer = int(val)
            else if (key == "vocab_size") vocab_size = int(val)
            else if (key == "block_size") block_size = int(val)
        }
    }
    close(file)

    head_dim = int(n_embd / n_head)
    hidden_dim = 4 * n_embd

    # Token embeddings [vocab_size, n_embd]
    load_weights(model_dir "/wte.txt", "wte", vocab_size * n_embd)

    # Position embeddings [block_size, n_embd]
    load_weights(model_dir "/wpe.txt", "wpe", block_size * n_embd)

    # Final layer norm
    load_weights(model_dir "/ln_f_weight.txt", "ln_f_w", n_embd)
    load_weights(model_dir "/ln_f_bias.txt", "ln_f_b", n_embd)

    # Per-layer weights
    for (layer = 0; layer < n_layer; layer++) {
        prefix = model_dir "/blocks/" layer

        # Attention layer norm
        load_weights(prefix "/ln1_weight.txt", "ln1_w_" layer, n_embd)
        load_weights(prefix "/ln1_bias.txt", "ln1_b_" layer, n_embd)

        # Attention QKV projection [n_embd, 3*n_embd]
        load_weights(prefix "/attn_weight.txt", "attn_w_" layer, n_embd * 3 * n_embd)
        load_weights(prefix "/attn_bias.txt", "attn_b_" layer, 3 * n_embd)

        # Attention output projection [n_embd, n_embd]
        load_weights(prefix "/attn_proj_weight.txt", "attn_proj_w_" layer, n_embd * n_embd)
        load_weights(prefix "/attn_proj_bias.txt", "attn_proj_b_" layer, n_embd)

        # FFN layer norm
        load_weights(prefix "/ln2_weight.txt", "ln2_w_" layer, n_embd)
        load_weights(prefix "/ln2_bias.txt", "ln2_b_" layer, n_embd)

        # FFN fc1 [n_embd, 4*n_embd]
        load_weights(prefix "/ffn_fc1_weight.txt", "ffn_fc1_w_" layer, n_embd * hidden_dim)
        load_weights(prefix "/ffn_fc1_bias.txt", "ffn_fc1_b_" layer, hidden_dim)

        # FFN fc2 [4*n_embd, n_embd]
        load_weights(prefix "/ffn_fc2_weight.txt", "ffn_fc2_w_" layer, hidden_dim * n_embd)
        load_weights(prefix "/ffn_fc2_bias.txt", "ffn_fc2_b_" layer, n_embd)
    }
}

function load_weights(file, name, expected_count,    line, i, val) {
    i = 1
    while ((getline line < file) > 0) {
        weights[name, i] = int(line)
        i++
    }
    close(file)
}

#=============================================================================
# FIXED-POINT MATH (for compatibility with bash version)
#=============================================================================

function fp_exp(x,    neg, result, term, i) {
    # Clamp
    if (x > 8 * SCALE) x = 8 * SCALE
    if (x < -8 * SCALE) return 0

    neg = 0
    if (x < 0) {
        neg = 1
        x = -x
    }

    result = SCALE
    term = SCALE

    for (i = 1; i <= 15; i++) {
        term = int((term * x) / (i * SCALE))
        result = result + term
        if (term < 1) break
    }

    if (neg) {
        if (result == 0) return 0
        result = int((SCALE * SCALE) / result)
    }

    return result
}

function fp_sqrt(x,    guess, prev, i, div, diff) {
    if (x <= 0) return 0

    guess = int(x / 2)
    if (guess < SCALE) guess = SCALE

    for (i = 0; i < 20; i++) {
        prev = guess
        div = int((x * SCALE) / guess)
        guess = int((guess + div) / 2)
        diff = guess - prev
        if (diff < 0) diff = -diff
        if (diff < 2) break
    }

    return guess
}

function fp_tanh(x,    exp_2x, num, denom) {
    if (x > 4 * SCALE) return SCALE
    if (x < -4 * SCALE) return -SCALE

    exp_2x = fp_exp(2 * x)
    num = exp_2x - SCALE
    denom = exp_2x + SCALE

    if (denom == 0) return SCALE

    return int((num * SCALE) / denom)
}

function fp_gelu(x,    sqrt_2_pi, coeff, x_sq, x_cu, cubic_term, inner, tanh_val, half_term) {
    sqrt_2_pi = 7979
    coeff = 447

    x_sq = int((x * x) / SCALE)
    x_cu = int((x_sq * x) / SCALE)
    cubic_term = int((coeff * x_cu) / SCALE)
    inner = x + cubic_term
    inner = int((sqrt_2_pi * inner) / SCALE)
    tanh_val = fp_tanh(inner)
    half_term = int((SCALE + tanh_val) / 2)

    return int((x * half_term) / SCALE)
}

function fp_softmax(arr, n, out,    i, max_val, sum, shifted, e) {
    # Find max
    max_val = arr[1]
    for (i = 2; i <= n; i++) {
        if (arr[i] > max_val) max_val = arr[i]
    }

    # Compute exp(x - max) and sum
    sum = 0
    for (i = 1; i <= n; i++) {
        shifted = arr[i] - max_val
        e = fp_exp(shifted)
        out[i] = e
        sum = sum + e
    }

    # Normalize
    for (i = 1; i <= n; i++) {
        if (sum > 0) {
            out[i] = int((out[i] * SCALE) / sum)
        } else {
            out[i] = int(SCALE / n)
        }
    }
}

#=============================================================================
# LAYER OPERATIONS
#=============================================================================

function layer_norm(input, start, gamma_name, beta_name, out, out_start,    i, sum, mean, var_sum, diff, variance, std, normalized, eps) {
    eps = 100

    # Compute mean
    sum = 0
    for (i = 1; i <= n_embd; i++) {
        sum = sum + input[start + i - 1]
    }
    mean = int(sum / n_embd)

    # Compute variance
    var_sum = 0
    for (i = 1; i <= n_embd; i++) {
        diff = input[start + i - 1] - mean
        var_sum = var_sum + int((diff * diff) / SCALE)
    }
    variance = int(var_sum / n_embd)

    # Standard deviation
    std = fp_sqrt(variance + eps)
    if (std < 100) std = 100

    # Normalize
    for (i = 1; i <= n_embd; i++) {
        normalized = int(((input[start + i - 1] - mean) * SCALE) / std)
        scaled = int((normalized * weights[gamma_name, i]) / SCALE)
        out[out_start + i - 1] = scaled + weights[beta_name, i]
    }
}

#=============================================================================
# ATTENTION
#=============================================================================

function multi_head_attention(hidden, seq_len, layer, out,    t, i, j, d, h, sum, qkv_dim, \
                              q_start, k_start, v_start, head_offset, score, scale, \
                              attn_sum, w_idx, c_start) {
    qkv_dim = 3 * n_embd

    # Project to Q, K, V
    for (t = 1; t <= seq_len; t++) {
        for (i = 1; i <= qkv_dim; i++) {
            sum = weights["attn_b_" layer, i]
            for (j = 1; j <= n_embd; j++) {
                w_idx = (j - 1) * qkv_dim + i
                sum = sum + int((hidden[(t-1) * n_embd + j] * weights["attn_w_" layer, w_idx]) / SCALE)
            }
            qkv[(t-1) * qkv_dim + i] = sum
        }
    }

    # Compute attention for each head
    scale = fp_sqrt(head_dim * SCALE)

    for (h = 0; h < n_head; h++) {
        head_offset = h * head_dim

        # Extract Q, K, V for this head and compute attention
        for (i = 1; i <= seq_len; i++) {
            for (d = 1; d <= head_dim; d++) {
                Q_h[(i-1) * head_dim + d] = qkv[(i-1) * qkv_dim + head_offset + d]
                K_h[(i-1) * head_dim + d] = qkv[(i-1) * qkv_dim + n_embd + head_offset + d]
                V_h[(i-1) * head_dim + d] = qkv[(i-1) * qkv_dim + 2*n_embd + head_offset + d]
            }
        }

        # Compute attention scores and apply to values
        for (i = 1; i <= seq_len; i++) {
            # Compute scores for this query position
            for (j = 1; j <= seq_len; j++) {
                if (j > i) {
                    # Causal mask
                    attn_scores[j] = -1000000000
                } else {
                    score = 0
                    for (d = 1; d <= head_dim; d++) {
                        score = score + int((Q_h[(i-1) * head_dim + d] * K_h[(j-1) * head_dim + d]) / SCALE)
                    }
                    attn_scores[j] = int((score * SCALE) / scale)
                }
            }

            # Softmax
            fp_softmax(attn_scores, seq_len, attn_probs)

            # Apply to values
            for (d = 1; d <= head_dim; d++) {
                attn_sum = 0
                for (j = 1; j <= seq_len; j++) {
                    attn_sum = attn_sum + int((attn_probs[j] * V_h[(j-1) * head_dim + d]) / SCALE)
                }
                head_out[h, (i-1) * head_dim + d] = attn_sum
            }
        }
    }

    # Concatenate heads
    for (t = 1; t <= seq_len; t++) {
        for (h = 0; h < n_head; h++) {
            for (d = 1; d <= head_dim; d++) {
                concat[(t-1) * n_embd + h * head_dim + d] = head_out[h, (t-1) * head_dim + d]
            }
        }
    }

    # Output projection
    for (t = 1; t <= seq_len; t++) {
        for (i = 1; i <= n_embd; i++) {
            sum = weights["attn_proj_b_" layer, i]
            for (j = 1; j <= n_embd; j++) {
                w_idx = (j - 1) * n_embd + i
                sum = sum + int((concat[(t-1) * n_embd + j] * weights["attn_proj_w_" layer, w_idx]) / SCALE)
            }
            out[(t-1) * n_embd + i] = sum
        }
    }
}

#=============================================================================
# FEED-FORWARD NETWORK
#=============================================================================

function feed_forward(hidden, seq_len, layer, out,    t, i, j, sum, w_idx, gelu_val) {
    for (t = 1; t <= seq_len; t++) {
        # FC1: n_embd -> 4*n_embd with GELU
        for (i = 1; i <= hidden_dim; i++) {
            sum = weights["ffn_fc1_b_" layer, i]
            for (j = 1; j <= n_embd; j++) {
                w_idx = (j - 1) * hidden_dim + i
                sum = sum + int((hidden[(t-1) * n_embd + j] * weights["ffn_fc1_w_" layer, w_idx]) / SCALE)
            }
            intermediate[i] = fp_gelu(sum)
        }

        # FC2: 4*n_embd -> n_embd
        for (i = 1; i <= n_embd; i++) {
            sum = weights["ffn_fc2_b_" layer, i]
            for (j = 1; j <= hidden_dim; j++) {
                w_idx = (j - 1) * n_embd + i
                sum = sum + int((intermediate[j] * weights["ffn_fc2_w_" layer, w_idx]) / SCALE)
            }
            out[(t-1) * n_embd + i] = sum
        }
    }
}

#=============================================================================
# TRANSFORMER BLOCK
#=============================================================================

function transformer_block(hidden, seq_len, layer, out,    t, i) {
    # Pre-norm for attention
    for (t = 1; t <= seq_len; t++) {
        layer_norm(hidden, (t-1) * n_embd + 1, "ln1_w_" layer, "ln1_b_" layer, normed1, (t-1) * n_embd + 1)
    }

    # Multi-head attention
    multi_head_attention(normed1, seq_len, layer, attn_out)

    # Residual connection
    for (i = 1; i <= seq_len * n_embd; i++) {
        residual1[i] = hidden[i] + attn_out[i]
    }

    # Pre-norm for FFN
    for (t = 1; t <= seq_len; t++) {
        layer_norm(residual1, (t-1) * n_embd + 1, "ln2_w_" layer, "ln2_b_" layer, normed2, (t-1) * n_embd + 1)
    }

    # Feed-forward
    feed_forward(normed2, seq_len, layer, ffn_out)

    # Residual connection
    for (i = 1; i <= seq_len * n_embd; i++) {
        out[i] = residual1[i] + ffn_out[i]
    }
}

#=============================================================================
# FORWARD PASS
#=============================================================================

function forward(tokens, seq_len,    t, i, layer, tok_idx, pos_idx, last_start, v, emb_start, sum) {
    if (seq_len > block_size) seq_len = block_size

    # Token + position embeddings
    for (t = 1; t <= seq_len; t++) {
        tok_idx = (tokens[t] * n_embd)
        pos_idx = ((t - 1) * n_embd)

        for (i = 1; i <= n_embd; i++) {
            hidden[t, i] = weights["wte", tok_idx + i] + weights["wpe", pos_idx + i]
            block_hidden[(t-1) * n_embd + i] = hidden[t, i]
        }
    }

    # Transformer blocks
    for (layer = 0; layer < n_layer; layer++) {
        transformer_block(block_hidden, seq_len, layer, block_out)

        # Copy output to input for next layer
        for (i = 1; i <= seq_len * n_embd; i++) {
            block_hidden[i] = block_out[i]
        }
    }

    # Final layer norm (only last position)
    last_start = (seq_len - 1) * n_embd + 1
    layer_norm(block_hidden, last_start, "ln_f_w", "ln_f_b", final_normed, 1)

    # Project to vocabulary
    for (v = 1; v <= vocab_size; v++) {
        emb_start = (v - 1) * n_embd
        sum = 0
        for (i = 1; i <= n_embd; i++) {
            sum = sum + int((final_normed[i] * weights["wte", emb_start + i]) / SCALE)
        }
        logits[v] = sum
    }
}
