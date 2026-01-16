# LLM Architecture: The Bash Transformer

> "We've parsed JSON with sed. We've built HTTP servers with netcat. Now we teach bash to think."

## The Audacity

This document describes `llm-service` - a **working** large language model inference engine written entirely in bash. No Python at runtime. No PyTorch. No external dependencies. Just bash, fixed-point arithmetic, and Taylor series approximations.

We implemented a GPT-style transformer from scratch. In bash. It generates text. Slowly. That's the point.

---

## What Actually Works

### Verified Capabilities

| Feature | Status | Notes |
|---------|--------|-------|
| Model loading | ✅ Works | Loads 70K params in ~15 seconds |
| Forward pass | ✅ Works | Full transformer inference |
| Text generation | ✅ Works | Autoregressive, token by token |
| HTTP API | ✅ Works | REST endpoints on port 8004 |
| Training | ✅ Works | Python script exports to bash format |

### Actual Benchmarks

Tested on a trained Shakespeare model (70,464 parameters):

| Metric | Value |
|--------|-------|
| Model load time | ~15 seconds |
| Tokens per second | ~0.07 (14 sec/token) |
| 2 tokens generation | 28 seconds |
| 5 tokens generation | ~265 seconds (4.4 min) |

The speed scales with context length. Longer prompts = slower generation.

### Sample Output

```
Input:  "To be or not to be"
Output: "To be or not to beqjbE+"
Time:   265 seconds

Input:  "ROMEO: "
Output: "ROMEO: HelloO?"
Time:   28 seconds
```

It's not Shakespeare. But it's bash computing attention weights.

---

## Architecture

### The Stack

```
lib/math.sh        →  Fixed-point arithmetic (exp, tanh, sqrt, gelu, softmax)
       ↓
lib/matrix.sh      →  Matrix operations (matmul, transpose, layer_norm)
       ↓
lib/transformer.sh →  Transformer components (attention, FFN, blocks)
       ↓
llm.sh             →  HTTP service (netcat-based, port 8004)
```

### Model Architecture

```
Token Embeddings (256 × 48)
         ↓
Position Embeddings (32 × 48)
         ↓
    ┌────────────────────────────────────┐
    │         Transformer Block 0        │
    │  ┌──────────────────────────────┐  │
    │  │ LayerNorm → MultiHeadAttn   │  │
    │  │         (2 heads)            │  │
    │  └──────────────────────────────┘  │
    │  ┌──────────────────────────────┐  │
    │  │ LayerNorm → FFN (48→192→48) │  │
    │  │         + GELU               │  │
    │  └──────────────────────────────┘  │
    └────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────┐
    │         Transformer Block 1        │
    │           (same structure)         │
    └────────────────────────────────────┘
         ↓
    Final LayerNorm
         ↓
    Logits (project to vocab)
         ↓
    Softmax → Sample
```

### Current Model Config

```
n_embd:     48        # Embedding dimension
n_head:     2         # Attention heads
n_layer:    2         # Transformer blocks
vocab_size: 256       # Byte-level tokenization
block_size: 32        # Max context length
head_dim:   24        # Per-head dimension
hidden_dim: 192       # FFN intermediate (4x)

Total parameters: 70,464
```

---

## Technical Decisions

### Fixed-Point Arithmetic

Bash only supports integers. We use scale factor 10000:

```bash
# 1.5 becomes 15000
# Multiply: (a * b) / 10000
# Division: (a * 10000) / b
SCALE=10000
```

Precision: ~4 decimal places. Good enough for transformers (8-bit quantization works, we're doing ~14-bit).

### Activation Functions

**GELU:** Approximated using the formula `x * 0.5 * (1 + tanh(√(2/π) * (x + 0.044715x³)))`

**Softmax:** Taylor series for exp(), with max subtraction for numerical stability.

**Tanh:** Taylor series, clamped to ±1 for large inputs.

**Sqrt:** Newton's method iteration.

### Character-Level Tokenization

- Vocabulary: 256 (one per byte)
- No tokenizer files needed
- ASCII value = token ID
- Works with any input

---

## API Reference

### Endpoints

```
GET  /health      →  Service status and model info
POST /generate    →  Generate text
POST /tokenize    →  Convert text to token IDs
POST /detokenize  →  Convert token IDs to text
GET  /config      →  Model configuration
POST /reload      →  Reload model from disk
```

### Generate Request

```bash
curl -X POST http://localhost:8004/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello", "max_tokens": 5}'
```

Response:
```json
{
  "generated": "Hello world",
  "tokens": 5,
  "time_seconds": 70,
  "warning": "this is bash inference, time is a feature not a bug"
}
```

---

## Training Your Own Model

We include a minimal PyTorch training script:

```bash
cd todo-microservices/llm-service

# Install PyTorch
pip install torch

# Train on built-in Shakespeare (2 minutes)
python train_model.py --sample

# Train on custom text
python train_model.py --data yourtext.txt --iters 3000
```

The script:
1. Trains a tiny character-level transformer
2. Exports weights to fixed-point text format
3. Places them in `model/` ready for bash inference

---

## File Structure

```
llm-service/
├── llm.sh              # HTTP service (port 8004)
├── train_model.py      # PyTorch training + export
├── init_model.sh       # Generate random weights for testing
├── lib/
│   ├── math.sh         # Fixed-point: exp, tanh, sqrt, gelu, softmax
│   ├── matrix.sh       # Matrix ops: matmul, transpose, layer_norm
│   └── transformer.sh  # Transformer: attention, FFN, blocks
└── model/
    ├── config.txt      # Model hyperparameters
    ├── wte.txt         # Token embeddings [256 × 48]
    ├── wpe.txt         # Position embeddings [32 × 48]
    ├── ln_f_weight.txt # Final layer norm
    ├── ln_f_bias.txt
    └── blocks/
        ├── 0/          # Layer 0 weights
        │   ├── ln1_weight.txt, ln1_bias.txt
        │   ├── attn_weight.txt, attn_bias.txt
        │   ├── attn_proj_weight.txt, attn_proj_bias.txt
        │   ├── ln2_weight.txt, ln2_bias.txt
        │   ├── ffn_fc1_weight.txt, ffn_fc1_bias.txt
        │   └── ffn_fc2_weight.txt, ffn_fc2_bias.txt
        └── 1/          # Layer 1 weights (same structure)
```

---

## What Could Go Wrong

This is experimental. Known limitations:

- **Speed**: ~14 seconds per token. That's not a typo.
- **Precision**: Fixed-point arithmetic loses some accuracy
- **Context**: Limited to 32 tokens (model constraint, not bash)
- **Quality**: 70K params trained for 2 minutes = creative gibberish
- **Memory**: Large contexts may strain bash array limits

What works:
- The math is correct (verified against PyTorch)
- Generation produces actual tokens
- The architecture matches GPT-2 style transformers

---

## Why?

We're not building a good LLM. We're building an LLM in bash.

The goal isn't speed or accuracy. The goal is to prove that:
1. The transformer architecture is simple enough to implement anywhere
2. Bash can do matrix multiplication (slowly)
3. Taylor series work for neural network activations
4. This project has no boundaries it won't cross

---

## Future Possibilities

Things we might do (or might not, who knows):

- [ ] Integrate with the todo app (AI-powered task suggestions?)
- [ ] Train on todo-related text
- [ ] Implement KV caching (speed up generation 2x)
- [ ] Add temperature parameter to API
- [ ] Port to pure POSIX sh (remove bashisms)
- [ ] Larger model support (if you have hours to wait)

---

*"The reasonable man adapts himself to the world. The unreasonable one persists in trying to implement GPT in bash. Therefore all progress depends on the unreasonable man."*
— George Bernard Shaw (probably)
