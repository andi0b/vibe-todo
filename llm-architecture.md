# LLM Architecture: The AWK Transformer

> "We've parsed JSON with sed. We've built HTTP servers with netcat. Now we teach AWK to think."

## The Audacity

This document describes `llm-service` - a **working** large language model inference engine. The forward pass runs in AWK. With bash orchestration. No Python at runtime. No PyTorch. No external dependencies. Just AWK, fixed-point arithmetic, and Taylor series approximations.

We implemented a GPT-style transformer from scratch. First in bash, then rewrote it in AWK because we asked "can we go faster?" instead of "should we stop?".

---

## What Actually Works

### Verified Capabilities

| Feature | Status | Notes |
|---------|--------|-------|
| Model loading | ✅ Works | AWK loads weights on each forward pass |
| Forward pass | ✅ Works | Full transformer in AWK |
| Text generation | ✅ Works | Autoregressive, token by token |
| HTTP API | ✅ Works | REST endpoints on port 8004 |
| Training | ✅ Works | Python script exports to AWK-compatible format |
| Python reference | ✅ Works | Verifies AWK output matches exactly |

### Sample Output

```
Input:  "ROMEO: "
Output: "ROMEO: HelloO?"

Input:  "To be or not to be"
Output: "To be or not to be..."
```

It's not Shakespeare. But it's AWK computing attention weights.

---

## Architecture

### The Stack

```
lib/transformer.awk →  The entire forward pass in AWK
        ↓
lib/awk_forward.sh  →  Bash wrapper for generation loop
        ↓
lib/math.sh         →  Fixed-point arithmetic for sampling
        ↓
llm.sh              →  HTTP service (netcat-based, port 8004)
```

### Model Architecture

```
Token Embeddings (256 × 64)
         ↓
Position Embeddings (64 × 64)
         ↓
    ┌────────────────────────────────────┐
    │         Transformer Block 0        │
    │  ┌──────────────────────────────┐  │
    │  │ LayerNorm → MultiHeadAttn   │  │
    │  │         (4 heads)            │  │
    │  └──────────────────────────────┘  │
    │  ┌──────────────────────────────┐  │
    │  │ LayerNorm → FFN (64→256→64) │  │
    │  │         + GELU               │  │
    │  └──────────────────────────────┘  │
    └────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────┐
    │         Transformer Block 1        │
    │           (same structure)         │
    └────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────┐
    │         Transformer Block 2        │
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
n_embd:     64        # Embedding dimension
n_head:     4         # Attention heads
n_layer:    3         # Transformer blocks
vocab_size: 256       # Byte-level tokenization
block_size: 64        # Max context length
head_dim:   16        # Per-head dimension (64/4)
hidden_dim: 256       # FFN intermediate (4×64)
```

---

## Technical Decisions

### Why AWK?

The original bash implementation was... slow. Like, 14 seconds per token slow. AWK gave us:
- Actual floating point (well, we still use fixed-point for compatibility)
- Faster loops
- Arrays that don't make you cry
- Still no dependencies

The forward pass went from pure bash to AWK. Bash still handles the HTTP server, generation loop, and sampling. AWK does the heavy lifting.

### Fixed-Point Arithmetic

AWK has floats, but we kept fixed-point for consistency with the bash math library:

```awk
SCALE = 10000
# 1.5 becomes 15000
# Multiply: (a * b) / SCALE
# Division: (a * SCALE) / b
```

### Activation Functions

**GELU:** `x * 0.5 * (1 + tanh(√(2/π) * (x + 0.044715x³)))`

**Softmax:** exp() with max subtraction for numerical stability.

**Tanh:** Taylor series, clamped to ±1 for large inputs.

**Sqrt:** Newton's method iteration.

All implemented in AWK. All verified against Python.

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
  "warning": "this is AWK inference, patience is a virtue"
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
3. Places them in `model/` ready for AWK inference

---

## File Structure

```
llm-service/
├── llm.sh              # HTTP service (port 8004)
├── train_model.py      # PyTorch training + export
├── forward_reference.py # Python implementation for verification
├── init_model.sh       # Generate random weights for testing
├── lib/
│   ├── transformer.awk # The entire forward pass in AWK
│   ├── awk_forward.sh  # Bash wrapper for generation
│   ├── math.sh         # Fixed-point: exp, tanh, sqrt, gelu, softmax
│   ├── matrix.sh       # Matrix ops (legacy bash version)
│   └── transformer.sh  # Transformer ops (legacy bash version)
└── model/
    ├── config.txt      # Model hyperparameters
    ├── wte.txt         # Token embeddings [256 × 64]
    ├── wpe.txt         # Position embeddings [64 × 64]
    ├── ln_f_weight.txt # Final layer norm
    ├── ln_f_bias.txt
    └── blocks/
        ├── 0/          # Layer 0 weights
        ├── 1/          # Layer 1 weights
        └── 2/          # Layer 2 weights
```

---

## Verification

The Python reference implementation (`forward_reference.py`) loads the same weights and computes the same forward pass. Both produce identical output tokens. This proves:

1. The AWK math is correct
2. The architecture matches GPT-2 style transformers
3. We're not just generating random noise (well, not *just* random noise)

---

## What Could Go Wrong

Known limitations:

- **Speed**: Still a few seconds per token. That's the AWK life.
- **Precision**: Fixed-point arithmetic loses some accuracy
- **Context**: Limited to 64 tokens (model constraint)
- **Quality**: Trained on Shakespeare for a few minutes = creative gibberish

What works:
- The math is correct (verified against Python)
- Generation produces actual tokens
- AWK and Python agree on every token

---

## Why?

We're not building a good LLM. We're building an LLM in AWK.

The goal isn't speed or accuracy. The goal is to prove that:
1. The transformer architecture is simple enough to implement anywhere
2. AWK can do matrix multiplication
3. Taylor series work for neural network activations
4. This project has no boundaries it won't cross

---

## Future Possibilities

Things we might do (or might not, who knows):

- [ ] Integrate with the todo app (AI-powered task suggestions?)
- [ ] Train on todo-related text
- [ ] Implement KV caching (speed up generation)
- [ ] Add temperature parameter to API
- [ ] Port to pure POSIX awk (remove gawk-isms)

---

*"The reasonable man adapts himself to the world. The unreasonable one persists in trying to implement GPT in AWK. Therefore all progress depends on the unreasonable man."*
— George Bernard Shaw (probably)
