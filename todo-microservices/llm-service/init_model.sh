#!/bin/bash
# Initialize a random model for testing the bash LLM
# This generates garbage output but proves the architecture works

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$SCRIPT_DIR/model"

# Model config - slightly bigger because AWK makes us brave
N_EMBD=64        # Embedding dimension (divisible by N_HEAD)
N_HEAD=4         # Number of attention heads (more attention = more drama)
N_LAYER=3        # Number of transformer layers (deeper thoughts)
VOCAB_SIZE=256   # Byte-level vocabulary
BLOCK_SIZE=64    # Maximum context length (more room for monologues)

HEAD_DIM=$((N_EMBD / N_HEAD))
HIDDEN_DIM=$((4 * N_EMBD))  # FFN hidden dimension

SCALE=10000

echo "=== Initializing Random Model ==="
echo "Config:"
echo "  n_embd:     $N_EMBD"
echo "  n_head:     $N_HEAD"
echo "  n_layer:    $N_LAYER"
echo "  vocab_size: $VOCAB_SIZE"
echo "  block_size: $BLOCK_SIZE"
echo "  head_dim:   $HEAD_DIM"
echo "  hidden_dim: $HIDDEN_DIM"
echo

# Xavier/Glorot-ish initialization: scale by 1/sqrt(fan_in)
# We'll use simpler uniform random scaled appropriately
random_weight() {
    local limit="$1"
    echo $(( (RANDOM * 2 * limit / 32768) - limit ))
}

# Generate N random weights to file
generate_weights() {
    local file="$1"
    local count="$2"
    local limit="${3:-1000}"  # Default: [-0.1, 0.1]

    echo -n "  Generating $file ($count values)... "
    > "$file"
    for ((i=0; i<count; i++)); do
        echo "$(random_weight "$limit")" >> "$file"
    done
    echo "done"
}

# Generate bias (usually zeros or small)
generate_bias() {
    local file="$1"
    local count="$2"

    echo -n "  Generating $file ($count values, zeros)... "
    > "$file"
    for ((i=0; i<count; i++)); do
        echo "0" >> "$file"
    done
    echo "done"
}

# Generate ones (for layer norm gamma)
generate_ones() {
    local file="$1"
    local count="$2"

    echo -n "  Generating $file ($count values, ones)... "
    > "$file"
    for ((i=0; i<count; i++)); do
        echo "$SCALE" >> "$file"
    done
    echo "done"
}

# Create directory structure
echo "Creating directories..."
mkdir -p "$MODEL_DIR/blocks"
for ((layer=0; layer<N_LAYER; layer++)); do
    mkdir -p "$MODEL_DIR/blocks/$layer"
done

# Write config
echo "Writing config..."
cat > "$MODEL_DIR/config.txt" << EOF
n_embd=$N_EMBD
n_head=$N_HEAD
n_layer=$N_LAYER
vocab_size=$VOCAB_SIZE
block_size=$BLOCK_SIZE
EOF

# Token embeddings [vocab_size, n_embd]
echo "Generating embeddings..."
generate_weights "$MODEL_DIR/wte.txt" $((VOCAB_SIZE * N_EMBD)) 2000

# Position embeddings [block_size, n_embd]
generate_weights "$MODEL_DIR/wpe.txt" $((BLOCK_SIZE * N_EMBD)) 1000

# Final layer norm
echo "Generating final layer norm..."
generate_ones "$MODEL_DIR/ln_f_weight.txt" $N_EMBD
generate_bias "$MODEL_DIR/ln_f_bias.txt" $N_EMBD

# Per-layer weights
for ((layer=0; layer<N_LAYER; layer++)); do
    echo "Generating layer $layer..."
    prefix="$MODEL_DIR/blocks/$layer"

    # Attention layer norm
    generate_ones "$prefix/ln1_weight.txt" $N_EMBD
    generate_bias "$prefix/ln1_bias.txt" $N_EMBD

    # Attention QKV projection [n_embd, 3*n_embd]
    generate_weights "$prefix/attn_weight.txt" $((N_EMBD * 3 * N_EMBD)) 1000
    generate_bias "$prefix/attn_bias.txt" $((3 * N_EMBD))

    # Attention output projection [n_embd, n_embd]
    generate_weights "$prefix/attn_proj_weight.txt" $((N_EMBD * N_EMBD)) 1000
    generate_bias "$prefix/attn_proj_bias.txt" $N_EMBD

    # FFN layer norm
    generate_ones "$prefix/ln2_weight.txt" $N_EMBD
    generate_bias "$prefix/ln2_bias.txt" $N_EMBD

    # FFN fc1 [n_embd, 4*n_embd]
    generate_weights "$prefix/ffn_fc1_weight.txt" $((N_EMBD * HIDDEN_DIM)) 1000
    generate_bias "$prefix/ffn_fc1_bias.txt" $HIDDEN_DIM

    # FFN fc2 [4*n_embd, n_embd]
    generate_weights "$prefix/ffn_fc2_weight.txt" $((HIDDEN_DIM * N_EMBD)) 1000
    generate_bias "$prefix/ffn_fc2_bias.txt" $N_EMBD
done

# Count total parameters
total=0
for f in $(find "$MODEL_DIR" -name "*.txt" -type f ! -name "config.txt"); do
    count=$(wc -l < "$f")
    total=$((total + count))
done

echo
echo "=== Model Initialized ==="
echo "Total parameters: $total"
echo "Location: $MODEL_DIR"
echo
echo "This model has random weights and will generate garbage."
echo "But it's YOUR garbage, computed entirely in bash."
