#!/usr/bin/env python3
"""
Tiny GPT Trainer for Bash LLM
=============================
A minimal character-level transformer trainer.
Outputs weights in the format our bash transformer expects.

Usage:
    python train_model.py                    # Train on built-in Shakespeare sample
    python train_model.py --data myfile.txt  # Train on custom text
    python train_model.py --iters 5000       # More training iterations

Requirements:
    pip install torch
"""

import os
import math
import argparse
import torch
import torch.nn as nn
import torch.nn.functional as F

# === Model Config (matches our bash implementation) ===
# Bumped slightly because we believe in the power of AWK
N_EMBD = 64      # was 48 - more dimensions, more vibes
N_HEAD = 4       # was 2  - attention is all you need (x4)
N_LAYER = 3      # was 2  - deeper thoughts
VOCAB_SIZE = 256 # Byte-level (keep it simple)
BLOCK_SIZE = 64  # was 32 - longer context for Shakespeare's monologues
DROPOUT = 0.1

# === Fixed-point scale (must match bash) ===
SCALE = 10000


class SelfAttention(nn.Module):
    def __init__(self):
        super().__init__()
        self.c_attn = nn.Linear(N_EMBD, 3 * N_EMBD)
        self.c_proj = nn.Linear(N_EMBD, N_EMBD)
        self.attn_dropout = nn.Dropout(DROPOUT)
        self.resid_dropout = nn.Dropout(DROPOUT)
        # Causal mask
        self.register_buffer("mask", torch.tril(torch.ones(BLOCK_SIZE, BLOCK_SIZE))
                             .view(1, 1, BLOCK_SIZE, BLOCK_SIZE))

    def forward(self, x):
        B, T, C = x.size()
        # Calculate Q, K, V
        qkv = self.c_attn(x)
        q, k, v = qkv.split(N_EMBD, dim=2)

        # Reshape for multi-head attention
        head_dim = C // N_HEAD
        q = q.view(B, T, N_HEAD, head_dim).transpose(1, 2)
        k = k.view(B, T, N_HEAD, head_dim).transpose(1, 2)
        v = v.view(B, T, N_HEAD, head_dim).transpose(1, 2)

        # Attention
        att = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(head_dim))
        att = att.masked_fill(self.mask[:, :, :T, :T] == 0, float('-inf'))
        att = F.softmax(att, dim=-1)
        att = self.attn_dropout(att)

        y = att @ v
        y = y.transpose(1, 2).contiguous().view(B, T, C)
        y = self.resid_dropout(self.c_proj(y))
        return y


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.c_fc = nn.Linear(N_EMBD, 4 * N_EMBD)
        self.c_proj = nn.Linear(4 * N_EMBD, N_EMBD)
        self.dropout = nn.Dropout(DROPOUT)

    def forward(self, x):
        x = self.c_fc(x)
        x = F.gelu(x)
        x = self.c_proj(x)
        x = self.dropout(x)
        return x


class Block(nn.Module):
    def __init__(self):
        super().__init__()
        self.ln_1 = nn.LayerNorm(N_EMBD)
        self.attn = SelfAttention()
        self.ln_2 = nn.LayerNorm(N_EMBD)
        self.mlp = MLP()

    def forward(self, x):
        x = x + self.attn(self.ln_1(x))
        x = x + self.mlp(self.ln_2(x))
        return x


class TinyGPT(nn.Module):
    def __init__(self):
        super().__init__()
        self.wte = nn.Embedding(VOCAB_SIZE, N_EMBD)  # Token embeddings
        self.wpe = nn.Embedding(BLOCK_SIZE, N_EMBD)  # Position embeddings
        self.drop = nn.Dropout(DROPOUT)
        self.blocks = nn.ModuleList([Block() for _ in range(N_LAYER)])
        self.ln_f = nn.LayerNorm(N_EMBD)

        # Init weights
        self.apply(self._init_weights)

    def _init_weights(self, module):
        if isinstance(module, nn.Linear):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
            if module.bias is not None:
                torch.nn.init.zeros_(module.bias)
        elif isinstance(module, nn.Embedding):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)

    def forward(self, idx, targets=None):
        B, T = idx.size()
        pos = torch.arange(0, T, dtype=torch.long, device=idx.device)

        tok_emb = self.wte(idx)
        pos_emb = self.wpe(pos)
        x = self.drop(tok_emb + pos_emb)

        for block in self.blocks:
            x = block(x)

        x = self.ln_f(x)
        logits = x @ self.wte.weight.T  # Weight tying

        loss = None
        if targets is not None:
            loss = F.cross_entropy(logits.view(-1, VOCAB_SIZE), targets.view(-1))

        return logits, loss

    @torch.no_grad()
    def generate(self, idx, max_new_tokens, temperature=1.0):
        for _ in range(max_new_tokens):
            idx_cond = idx[:, -BLOCK_SIZE:]
            logits, _ = self(idx_cond)
            logits = logits[:, -1, :] / temperature
            probs = F.softmax(logits, dim=-1)
            idx_next = torch.multinomial(probs, num_samples=1)
            idx = torch.cat((idx, idx_next), dim=1)
        return idx


def to_fixed_point(tensor):
    """Convert float tensor to fixed-point integers."""
    return (tensor.float() * SCALE).round().long()


def export_weights(model, output_dir):
    """Export model weights to text files for bash consumption."""
    os.makedirs(output_dir, exist_ok=True)

    # Config
    with open(f"{output_dir}/config.txt", "w") as f:
        f.write(f"n_embd={N_EMBD}\n")
        f.write(f"n_head={N_HEAD}\n")
        f.write(f"n_layer={N_LAYER}\n")
        f.write(f"vocab_size={VOCAB_SIZE}\n")
        f.write(f"block_size={BLOCK_SIZE}\n")

    # Token embeddings [vocab_size, n_embd]
    wte = to_fixed_point(model.wte.weight.data)
    with open(f"{output_dir}/wte.txt", "w") as f:
        for row in wte:
            for val in row:
                f.write(f"{val.item()}\n")

    # Position embeddings [block_size, n_embd]
    wpe = to_fixed_point(model.wpe.weight.data)
    with open(f"{output_dir}/wpe.txt", "w") as f:
        for row in wpe:
            for val in row:
                f.write(f"{val.item()}\n")

    # Final layer norm
    ln_f_w = to_fixed_point(model.ln_f.weight.data)
    ln_f_b = to_fixed_point(model.ln_f.bias.data)
    with open(f"{output_dir}/ln_f_weight.txt", "w") as f:
        for val in ln_f_w:
            f.write(f"{val.item()}\n")
    with open(f"{output_dir}/ln_f_bias.txt", "w") as f:
        for val in ln_f_b:
            f.write(f"{val.item()}\n")

    # Per-layer weights
    for i, block in enumerate(model.blocks):
        block_dir = f"{output_dir}/blocks/{i}"
        os.makedirs(block_dir, exist_ok=True)

        # Attention layer norm
        write_tensor(to_fixed_point(block.ln_1.weight.data), f"{block_dir}/ln1_weight.txt")
        write_tensor(to_fixed_point(block.ln_1.bias.data), f"{block_dir}/ln1_bias.txt")

        # Attention QKV weights [n_embd, 3*n_embd]
        write_matrix(to_fixed_point(block.attn.c_attn.weight.data.T), f"{block_dir}/attn_weight.txt")
        write_tensor(to_fixed_point(block.attn.c_attn.bias.data), f"{block_dir}/attn_bias.txt")

        # Attention output projection [n_embd, n_embd]
        write_matrix(to_fixed_point(block.attn.c_proj.weight.data.T), f"{block_dir}/attn_proj_weight.txt")
        write_tensor(to_fixed_point(block.attn.c_proj.bias.data), f"{block_dir}/attn_proj_bias.txt")

        # FFN layer norm
        write_tensor(to_fixed_point(block.ln_2.weight.data), f"{block_dir}/ln2_weight.txt")
        write_tensor(to_fixed_point(block.ln_2.bias.data), f"{block_dir}/ln2_bias.txt")

        # FFN fc1 [n_embd, 4*n_embd]
        write_matrix(to_fixed_point(block.mlp.c_fc.weight.data.T), f"{block_dir}/ffn_fc1_weight.txt")
        write_tensor(to_fixed_point(block.mlp.c_fc.bias.data), f"{block_dir}/ffn_fc1_bias.txt")

        # FFN fc2 [4*n_embd, n_embd]
        write_matrix(to_fixed_point(block.mlp.c_proj.weight.data.T), f"{block_dir}/ffn_fc2_weight.txt")
        write_tensor(to_fixed_point(block.mlp.c_proj.bias.data), f"{block_dir}/ffn_fc2_bias.txt")

    print(f"Weights exported to {output_dir}/")


def write_tensor(tensor, path):
    with open(path, "w") as f:
        for val in tensor.flatten():
            f.write(f"{val.item()}\n")


def write_matrix(tensor, path):
    with open(path, "w") as f:
        for row in tensor:
            for val in row:
                f.write(f"{val.item()}\n")


# === Sample training data ===
SHAKESPEARE_SAMPLE = """
ROMEO: O, she doth teach the torches to burn bright!
It seems she hangs upon the cheek of night
Like a rich jewel in an Ethiope's ear;
Beauty too rich for use, for earth too dear!
So shows a snowy dove trooping with crows,
As yonder lady o'er her fellows shows.
The measure done, I'll watch her place of stand,
And, touching hers, make blessed my rude hand.
Did my heart love till now? forswear it, sight!
For I ne'er saw true beauty till this night.

JULIET: O Romeo, Romeo! wherefore art thou Romeo?
Deny thy father and refuse thy name;
Or, if thou wilt not, be but sworn my love,
And I'll no longer be a Capulet.

ROMEO: Shall I hear more, or shall I speak at this?

JULIET: 'Tis but thy name that is my enemy;
Thou art thyself, though not a Montague.
What's Montague? It is nor hand, nor foot,
Nor arm, nor face, nor any other part
Belonging to a man. O, be some other name!
What's in a name? That which we call a rose
By any other name would smell as sweet;
So Romeo would, were he not Romeo call'd,
Retain that dear perfection which he owes
Without that title. Romeo, doff thy name,
And for that name which is no part of thee
Take all myself.

ROMEO: I take thee at thy word:
Call me but love, and I'll be new baptized;
Henceforth I never will be Romeo.

HAMLET: To be, or not to be, that is the question:
Whether 'tis nobler in the mind to suffer
The slings and arrows of outrageous fortune,
Or to take arms against a sea of troubles
And by opposing end them. To die: to sleep;
No more; and by a sleep to say we end
The heart-ache and the thousand natural shocks
That flesh is heir to: 'tis a consummation
Devoutly to be wish'd. To die, to sleep;
To sleep: perchance to dream: ay, there's the rub;
For in that sleep of death what dreams may come,
When we have shuffled off this mortal coil,
Must give us pause: there's the respect
That makes calamity of so long life.

MACBETH: Tomorrow, and tomorrow, and tomorrow,
Creeps in this petty pace from day to day,
To the last syllable of recorded time;
And all our yesterdays have lighted fools
The way to dusty death. Out, out, brief candle!
Life's but a walking shadow, a poor player,
That struts and frets his hour upon the stage,
And then is heard no more. It is a tale
Told by an idiot, full of sound and fury,
Signifying nothing.
"""


def main():
    parser = argparse.ArgumentParser(description="Train a tiny GPT for bash inference")
    parser.add_argument("--data", type=str, help="Path to training text file")
    parser.add_argument("--iters", type=int, default=2000, help="Training iterations")
    parser.add_argument("--lr", type=float, default=3e-4, help="Learning rate")
    parser.add_argument("--batch", type=int, default=32, help="Batch size")
    parser.add_argument("--output", type=str, default="model", help="Output directory")
    parser.add_argument("--sample", action="store_true", help="Generate sample after training")
    args = parser.parse_args()

    # Load data
    if args.data:
        with open(args.data, 'r') as f:
            text = f.read()
        print(f"Loaded {len(text)} characters from {args.data}")
    else:
        text = SHAKESPEARE_SAMPLE
        print(f"Using built-in Shakespeare sample ({len(text)} chars)")

    # Encode as bytes
    data = torch.tensor([b for b in text.encode('utf-8')], dtype=torch.long)
    n = len(data)
    train_data = data[:int(n*0.9)]
    val_data = data[int(n*0.9):]

    print(f"Train: {len(train_data)} tokens, Val: {len(val_data)} tokens")

    # Create model
    model = TinyGPT()
    n_params = sum(p.numel() for p in model.parameters())
    print(f"Model parameters: {n_params:,}")

    # Training
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)

    def get_batch(split):
        data = train_data if split == 'train' else val_data
        ix = torch.randint(len(data) - BLOCK_SIZE, (args.batch,))
        x = torch.stack([data[i:i+BLOCK_SIZE] for i in ix])
        y = torch.stack([data[i+1:i+BLOCK_SIZE+1] for i in ix])
        return x, y

    print(f"\nTraining for {args.iters} iterations...")
    print("-" * 50)

    for iter in range(args.iters):
        # Training step
        model.train()
        xb, yb = get_batch('train')
        logits, loss = model(xb, yb)

        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        # Logging
        if iter % 200 == 0 or iter == args.iters - 1:
            model.eval()
            with torch.no_grad():
                xv, yv = get_batch('val')
                _, val_loss = model(xv, yv)
            print(f"iter {iter:4d} | train loss: {loss.item():.4f} | val loss: {val_loss.item():.4f}")

    print("-" * 50)
    print("Training complete!")

    # Generate sample
    if args.sample:
        model.eval()
        context = torch.tensor([[ord('R'), ord('O'), ord('M'), ord('E'), ord('O'), ord(':'), ord(' ')]], dtype=torch.long)
        generated = model.generate(context, max_new_tokens=200, temperature=0.8)
        output = bytes(generated[0].tolist()).decode('utf-8', errors='replace')
        print(f"\nSample generation:\n{output}")

    # Export weights
    print(f"\nExporting weights to {args.output}/...")
    export_weights(model, args.output)

    print("\nDone! Your bash transformer can now load these weights.")
    print(f"Start the LLM service and it will auto-load from {args.output}/")


if __name__ == "__main__":
    main()
