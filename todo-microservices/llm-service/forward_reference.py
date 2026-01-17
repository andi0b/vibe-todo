#!/usr/bin/env python3
"""
Transformer Forward Pass - Python Reference Implementation
For comparing against the AWK version that exists for reasons we don't discuss in polite company.

Usage:
    python forward_reference.py --model-dir model --tokens "72 101 108 108 111"

Outputs logits in the same fixed-point format as the AWK version.
"""

import argparse
import math
import os
from pathlib import Path


SCALE = 10000


def load_config(model_dir: Path) -> dict:
    """Load model configuration."""
    config = {}
    config_file = model_dir / "config.txt"

    with open(config_file) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                key, val = line.split("=", 1)
                config[key] = int(val)

    config["head_dim"] = config["n_embd"] // config["n_head"]
    config["hidden_dim"] = 4 * config["n_embd"]
    return config


def load_weights(filepath: Path) -> list[int]:
    """Load weights from file."""
    weights = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line:
                weights.append(int(line))
    return weights


def load_model(model_dir: Path) -> tuple[dict, dict]:
    """Load all model weights."""
    config = load_config(model_dir)
    weights = {}

    # Token and position embeddings
    weights["wte"] = load_weights(model_dir / "wte.txt")
    weights["wpe"] = load_weights(model_dir / "wpe.txt")

    # Final layer norm
    weights["ln_f_w"] = load_weights(model_dir / "ln_f_weight.txt")
    weights["ln_f_b"] = load_weights(model_dir / "ln_f_bias.txt")

    # Per-layer weights
    for layer in range(config["n_layer"]):
        prefix = model_dir / "blocks" / str(layer)

        weights[f"ln1_w_{layer}"] = load_weights(prefix / "ln1_weight.txt")
        weights[f"ln1_b_{layer}"] = load_weights(prefix / "ln1_bias.txt")

        weights[f"attn_w_{layer}"] = load_weights(prefix / "attn_weight.txt")
        weights[f"attn_b_{layer}"] = load_weights(prefix / "attn_bias.txt")

        weights[f"attn_proj_w_{layer}"] = load_weights(prefix / "attn_proj_weight.txt")
        weights[f"attn_proj_b_{layer}"] = load_weights(prefix / "attn_proj_bias.txt")

        weights[f"ln2_w_{layer}"] = load_weights(prefix / "ln2_weight.txt")
        weights[f"ln2_b_{layer}"] = load_weights(prefix / "ln2_bias.txt")

        weights[f"ffn_fc1_w_{layer}"] = load_weights(prefix / "ffn_fc1_weight.txt")
        weights[f"ffn_fc1_b_{layer}"] = load_weights(prefix / "ffn_fc1_bias.txt")

        weights[f"ffn_fc2_w_{layer}"] = load_weights(prefix / "ffn_fc2_weight.txt")
        weights[f"ffn_fc2_b_{layer}"] = load_weights(prefix / "ffn_fc2_bias.txt")

    return config, weights


# Fixed-point math (matching AWK/bash)

def fp_exp(x: int) -> int:
    """Fixed-point exponential."""
    if x > 8 * SCALE:
        x = 8 * SCALE
    if x < -8 * SCALE:
        return 0

    neg = False
    if x < 0:
        neg = True
        x = -x

    result = SCALE
    term = SCALE

    for i in range(1, 16):
        term = (term * x) // (i * SCALE)
        result += term
        if term < 1:
            break

    if neg:
        if result == 0:
            return 0
        result = (SCALE * SCALE) // result

    return result


def fp_sqrt(x: int) -> int:
    """Fixed-point square root via Newton's method."""
    if x <= 0:
        return 0

    guess = x // 2
    if guess < SCALE:
        guess = SCALE

    for _ in range(20):
        prev = guess
        div = (x * SCALE) // guess
        guess = (guess + div) // 2
        diff = abs(guess - prev)
        if diff < 2:
            break

    return guess


def fp_tanh(x: int) -> int:
    """Fixed-point tanh."""
    if x > 4 * SCALE:
        return SCALE
    if x < -4 * SCALE:
        return -SCALE

    exp_2x = fp_exp(2 * x)
    num = exp_2x - SCALE
    denom = exp_2x + SCALE

    if denom == 0:
        return SCALE

    return (num * SCALE) // denom


def fp_gelu(x: int) -> int:
    """Fixed-point GELU activation."""
    sqrt_2_pi = 7979
    coeff = 447

    x_sq = (x * x) // SCALE
    x_cu = (x_sq * x) // SCALE
    cubic_term = (coeff * x_cu) // SCALE
    inner = x + cubic_term
    inner = (sqrt_2_pi * inner) // SCALE
    tanh_val = fp_tanh(inner)
    half_term = (SCALE + tanh_val) // 2

    return (x * half_term) // SCALE


def fp_softmax(arr: list[int]) -> list[int]:
    """Fixed-point softmax."""
    max_val = max(arr)

    exps = []
    total = 0
    for x in arr:
        shifted = x - max_val
        e = fp_exp(shifted)
        exps.append(e)
        total += e

    result = []
    for e in exps:
        if total > 0:
            result.append((e * SCALE) // total)
        else:
            result.append(SCALE // len(arr))

    return result


def layer_norm(inp: list[int], gamma: list[int], beta: list[int]) -> list[int]:
    """Layer normalization."""
    n = len(inp)
    eps = 100

    # Mean
    mean = sum(inp) // n

    # Variance
    var_sum = sum((x - mean) ** 2 // SCALE for x in inp)
    variance = var_sum // n

    # Std
    std = fp_sqrt(variance + eps)
    if std < 100:
        std = 100

    # Normalize
    result = []
    for i in range(n):
        normalized = ((inp[i] - mean) * SCALE) // std
        scaled = (normalized * gamma[i]) // SCALE
        result.append(scaled + beta[i])

    return result


def multi_head_attention(hidden: list[list[int]], layer: int, config: dict, weights: dict) -> list[list[int]]:
    """Multi-head attention."""
    seq_len = len(hidden)
    n_embd = config["n_embd"]
    n_head = config["n_head"]
    head_dim = config["head_dim"]
    qkv_dim = 3 * n_embd

    attn_w = weights[f"attn_w_{layer}"]
    attn_b = weights[f"attn_b_{layer}"]
    proj_w = weights[f"attn_proj_w_{layer}"]
    proj_b = weights[f"attn_proj_b_{layer}"]

    # Project to Q, K, V
    qkv = []
    for t in range(seq_len):
        row = []
        for i in range(qkv_dim):
            s = attn_b[i]
            for j in range(n_embd):
                w_idx = j * qkv_dim + i
                s += (hidden[t][j] * attn_w[w_idx]) // SCALE
            row.append(s)
        qkv.append(row)

    # Compute attention for each head
    scale = fp_sqrt(head_dim * SCALE)
    all_head_outputs = [[] for _ in range(n_head)]

    for h in range(n_head):
        head_offset = h * head_dim

        # Extract Q, K, V for this head
        Q = [[qkv[t][head_offset + d] for d in range(head_dim)] for t in range(seq_len)]
        K = [[qkv[t][n_embd + head_offset + d] for d in range(head_dim)] for t in range(seq_len)]
        V = [[qkv[t][2 * n_embd + head_offset + d] for d in range(head_dim)] for t in range(seq_len)]

        # Compute attention
        for i in range(seq_len):
            scores = []
            for j in range(seq_len):
                if j > i:
                    scores.append(-1000000000)
                else:
                    score = sum((Q[i][d] * K[j][d]) // SCALE for d in range(head_dim))
                    scores.append((score * SCALE) // scale)

            probs = fp_softmax(scores)

            # Apply to values
            out_vec = []
            for d in range(head_dim):
                attn_sum = sum((probs[j] * V[j][d]) // SCALE for j in range(seq_len))
                out_vec.append(attn_sum)
            all_head_outputs[h].append(out_vec)

    # Concatenate heads
    concat = []
    for t in range(seq_len):
        row = []
        for h in range(n_head):
            row.extend(all_head_outputs[h][t])
        concat.append(row)

    # Output projection
    output = []
    for t in range(seq_len):
        row = []
        for i in range(n_embd):
            s = proj_b[i]
            for j in range(n_embd):
                w_idx = j * n_embd + i
                s += (concat[t][j] * proj_w[w_idx]) // SCALE
            row.append(s)
        output.append(row)

    return output


def feed_forward(hidden: list[list[int]], layer: int, config: dict, weights: dict) -> list[list[int]]:
    """Feed-forward network."""
    seq_len = len(hidden)
    n_embd = config["n_embd"]
    hidden_dim = config["hidden_dim"]

    fc1_w = weights[f"ffn_fc1_w_{layer}"]
    fc1_b = weights[f"ffn_fc1_b_{layer}"]
    fc2_w = weights[f"ffn_fc2_w_{layer}"]
    fc2_b = weights[f"ffn_fc2_b_{layer}"]

    output = []
    for t in range(seq_len):
        # FC1 with GELU
        intermediate = []
        for i in range(hidden_dim):
            s = fc1_b[i]
            for j in range(n_embd):
                w_idx = j * hidden_dim + i
                s += (hidden[t][j] * fc1_w[w_idx]) // SCALE
            intermediate.append(fp_gelu(s))

        # FC2
        row = []
        for i in range(n_embd):
            s = fc2_b[i]
            for j in range(hidden_dim):
                w_idx = j * n_embd + i
                s += (intermediate[j] * fc2_w[w_idx]) // SCALE
            row.append(s)
        output.append(row)

    return output


def transformer_block(hidden: list[list[int]], layer: int, config: dict, weights: dict) -> list[list[int]]:
    """Single transformer block."""
    seq_len = len(hidden)

    ln1_w = weights[f"ln1_w_{layer}"]
    ln1_b = weights[f"ln1_b_{layer}"]
    ln2_w = weights[f"ln2_w_{layer}"]
    ln2_b = weights[f"ln2_b_{layer}"]

    # Pre-norm for attention
    normed1 = [layer_norm(hidden[t], ln1_w, ln1_b) for t in range(seq_len)]

    # Attention
    attn_out = multi_head_attention(normed1, layer, config, weights)

    # Residual
    residual1 = [[hidden[t][i] + attn_out[t][i] for i in range(len(hidden[t]))] for t in range(seq_len)]

    # Pre-norm for FFN
    normed2 = [layer_norm(residual1[t], ln2_w, ln2_b) for t in range(seq_len)]

    # FFN
    ffn_out = feed_forward(normed2, layer, config, weights)

    # Residual
    output = [[residual1[t][i] + ffn_out[t][i] for i in range(len(residual1[t]))] for t in range(seq_len)]

    return output


def forward(tokens: list[int], config: dict, weights: dict) -> list[int]:
    """Full forward pass."""
    seq_len = len(tokens)
    if seq_len > config["block_size"]:
        seq_len = config["block_size"]
        tokens = tokens[:seq_len]

    n_embd = config["n_embd"]
    vocab_size = config["vocab_size"]
    n_layer = config["n_layer"]

    wte = weights["wte"]
    wpe = weights["wpe"]
    ln_f_w = weights["ln_f_w"]
    ln_f_b = weights["ln_f_b"]

    # Token + position embeddings
    hidden = []
    for t, tok in enumerate(tokens):
        tok_start = tok * n_embd
        pos_start = t * n_embd
        row = [wte[tok_start + i] + wpe[pos_start + i] for i in range(n_embd)]
        hidden.append(row)

    # Transformer blocks
    for layer in range(n_layer):
        hidden = transformer_block(hidden, layer, config, weights)

    # Final layer norm (last position only)
    last_hidden = layer_norm(hidden[-1], ln_f_w, ln_f_b)

    # Project to vocabulary
    logits = []
    for v in range(vocab_size):
        emb_start = v * n_embd
        s = sum((last_hidden[i] * wte[emb_start + i]) // SCALE for i in range(n_embd))
        logits.append(s)

    return logits


def main():
    parser = argparse.ArgumentParser(description="Python reference transformer forward pass")
    parser.add_argument("--model-dir", default="model", help="Model directory")
    parser.add_argument("--tokens", default="72 101 108 108 111", help="Space-separated token IDs")
    args = parser.parse_args()

    model_dir = Path(args.model_dir)
    tokens = [int(t) for t in args.tokens.split()]

    config, weights = load_model(model_dir)
    logits = forward(tokens, config, weights)

    print(" ".join(str(l) for l in logits))


if __name__ == "__main__":
    main()
