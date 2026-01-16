#!/bin/bash
# Fixed-Point Math Library for Bash LLM
# Because floating point is for cowards

# Scale factor: 10000 = 1.0
# This gives us 4 decimal places of precision
# Range: approximately -214748.3648 to 214748.3647 (32-bit safe operations)
SCALE=10000

# Convert float string to fixed-point integer
# Usage: fp_from_float "1.5" -> 15000
fp_from_float() {
    local float="$1"
    local sign=""

    # Handle negative
    if [[ "$float" == -* ]]; then
        sign="-"
        float="${float:1}"
    fi

    # Split on decimal point
    local int_part="${float%%.*}"
    local frac_part="${float#*.}"

    # If no decimal, just scale
    if [[ "$float" == "$int_part" ]]; then
        echo "${sign}$((int_part * SCALE))"
        return
    fi

    # Pad or truncate fractional part to 4 digits
    frac_part="${frac_part}0000"
    frac_part="${frac_part:0:4}"

    # Remove leading zeros for arithmetic
    frac_part=$((10#$frac_part))

    local result=$((int_part * SCALE + frac_part))
    echo "${sign}${result}"
}

# Convert fixed-point to float string (for display)
# Usage: fp_to_float 15000 -> "1.5000"
fp_to_float() {
    local fp="$1"
    local sign=""

    if [[ $fp -lt 0 ]]; then
        sign="-"
        fp=$((-fp))
    fi

    local int_part=$((fp / SCALE))
    local frac_part=$((fp % SCALE))

    printf "%s%d.%04d" "$sign" "$int_part" "$frac_part"
}

# Fixed-point multiplication
# Usage: fp_mul 15000 20000 -> 30000 (1.5 * 2.0 = 3.0)
fp_mul() {
    local a="$1" b="$2"
    # Multiply then divide by scale to maintain fixed-point
    echo $(( (a * b) / SCALE ))
}

# Fixed-point division
# Usage: fp_div 30000 20000 -> 15000 (3.0 / 2.0 = 1.5)
fp_div() {
    local a="$1" b="$2"
    # Multiply by scale first to maintain precision
    echo $(( (a * SCALE) / b ))
}

# Fixed-point addition (trivial but for completeness)
fp_add() {
    echo $(($1 + $2))
}

# Fixed-point subtraction
fp_sub() {
    echo $(($1 - $2))
}

# Square root via Newton's method
# Usage: fp_sqrt 40000 -> 20000 (sqrt(4.0) = 2.0)
fp_sqrt() {
    local x="$1"
    [[ $x -le 0 ]] && { echo 0; return; }

    # Initial guess: x/2 or SCALE (whichever is reasonable)
    local guess=$((x / 2))
    [[ $guess -lt SCALE ]] && guess=$SCALE

    local prev=0
    local i

    # Newton's method: guess = (guess + x/guess) / 2
    for ((i=0; i<20; i++)); do
        prev=$guess
        # x/guess in fixed-point
        local div=$(( (x * SCALE) / guess ))
        guess=$(( (guess + div) / 2 ))

        # Converged?
        local diff=$((guess - prev))
        [[ ${diff#-} -lt 2 ]] && break
    done

    echo "$guess"
}

# Exponential via Taylor series
# exp(x) = 1 + x + x²/2! + x³/3! + x⁴/4! + ...
# Usage: fp_exp 10000 -> ~27183 (e^1.0 ≈ 2.7183)
fp_exp() {
    local x="$1"

    # Clamp to prevent overflow (exp(8) is already ~2981)
    [[ $x -gt $((8 * SCALE)) ]] && x=$((8 * SCALE))
    [[ $x -lt $((-8 * SCALE)) ]] && { echo 0; return; }

    local result=$SCALE  # 1.0
    local term=$SCALE    # Current term
    local i

    for ((i=1; i<=12; i++)); do
        # term = term * x / i
        term=$(( (term * x) / (i * SCALE) ))
        result=$((result + term))

        # Stop if term is negligible
        [[ ${term#-} -lt 1 ]] && break
    done

    echo "$result"
}

# Natural log via series expansion
# Using ln(1+x) = x - x²/2 + x³/3 - x⁴/4 + ... for |x| < 1
# For larger values, use ln(x) = ln(x/e^n) + n
fp_ln() {
    local x="$1"

    [[ $x -le 0 ]] && { echo $((-100 * SCALE)); return; }  # -infinity approx

    # Normalize x to range [1, e) by dividing by e repeatedly
    local n=0
    local e_approx=27183  # e ≈ 2.7183 in fixed-point

    while [[ $x -gt $e_approx ]]; do
        x=$(( (x * SCALE) / e_approx ))
        ((n++))
    done

    while [[ $x -lt $SCALE ]]; do
        x=$(( (x * e_approx) / SCALE ))
        ((n--))
    done

    # Now x is in [1, e), compute ln(x) using series for ln(1 + y) where y = x - 1
    local y=$((x - SCALE))
    local result=0
    local term=$y
    local i

    for ((i=1; i<=15; i++)); do
        if ((i % 2 == 1)); then
            result=$((result + term / i))
        else
            result=$((result - term / i))
        fi
        term=$(( (term * y) / SCALE ))

        [[ ${term#-} -lt SCALE/1000 ]] && break
    done

    # Add back n * ln(e) = n * 1
    result=$((result + n * SCALE))

    echo "$result"
}

# Hyperbolic tangent: tanh(x) = (e^2x - 1) / (e^2x + 1)
# Usage: fp_tanh 10000 -> ~7616 (tanh(1.0) ≈ 0.7616)
fp_tanh() {
    local x="$1"

    # For large |x|, tanh approaches ±1
    [[ $x -gt $((4 * SCALE)) ]] && { echo "$SCALE"; return; }
    [[ $x -lt $((-4 * SCALE)) ]] && { echo "$((-SCALE))"; return; }

    local exp_2x=$(fp_exp $((2 * x)))
    local numerator=$((exp_2x - SCALE))
    local denominator=$((exp_2x + SCALE))

    [[ $denominator -eq 0 ]] && { echo "$SCALE"; return; }

    echo $(( (numerator * SCALE) / denominator ))
}

# Maximum of array (passed as arguments)
fp_max() {
    local max="$1"
    shift
    for val in "$@"; do
        [[ $val -gt $max ]] && max=$val
    done
    echo "$max"
}

# Sum of array (passed as arguments)
fp_sum() {
    local sum=0
    for val in "$@"; do
        sum=$((sum + val))
    done
    echo "$sum"
}

# Mean of array
fp_mean() {
    local sum=0
    local count=0
    for val in "$@"; do
        sum=$((sum + val))
        ((count++))
    done
    [[ $count -eq 0 ]] && { echo 0; return; }
    echo $((sum / count))
}

# Variance of array (given mean)
fp_variance() {
    local mean="$1"
    shift
    local sum_sq=0
    local count=0
    for val in "$@"; do
        local diff=$((val - mean))
        # Be careful with overflow: diff² might be large
        sum_sq=$(( sum_sq + (diff * diff) / SCALE ))
        ((count++))
    done
    [[ $count -eq 0 ]] && { echo 0; return; }
    echo $((sum_sq / count))
}

# Random fixed-point in range [-limit, limit]
# For weight initialization
fp_random() {
    local limit="${1:-$SCALE}"  # Default: [-1.0, 1.0]
    echo $(( (RANDOM * 2 * limit / 32768) - limit ))
}

# GELU activation: x * 0.5 * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))
# This is the approximation used in GPT-2
fp_gelu() {
    local x="$1"

    # sqrt(2/π) ≈ 0.7979 -> 7979
    local sqrt_2_pi=7979

    # 0.044715 -> 447 (scaled down for fixed-point sanity)
    local coeff=447

    # x³ (careful with overflow - do in steps)
    local x_sq=$(( (x * x) / SCALE ))
    local x_cu=$(( (x_sq * x) / SCALE ))

    # 0.044715 * x³
    local cubic_term=$(( (coeff * x_cu) / SCALE ))

    # x + 0.044715 * x³
    local inner=$((x + cubic_term))

    # sqrt(2/π) * (x + 0.044715 * x³)
    inner=$(( (sqrt_2_pi * inner) / SCALE ))

    # tanh(...)
    local tanh_val=$(fp_tanh "$inner")

    # 1 + tanh(...)
    local one_plus_tanh=$((SCALE + tanh_val))

    # 0.5 * (1 + tanh(...))
    local half_term=$((one_plus_tanh / 2))

    # x * 0.5 * (1 + tanh(...))
    echo $(( (x * half_term) / SCALE ))
}

# Softmax over array of logits
# Returns array of probabilities (space-separated)
# Usage: fp_softmax "1000 2000 3000" -> "900 2447 6654" (approximately)
fp_softmax() {
    local -a logits=($1)
    local n=${#logits[@]}

    # Find max for numerical stability
    local max="${logits[0]}"
    for ((i=1; i<n; i++)); do
        [[ ${logits[i]} -gt $max ]] && max=${logits[i]}
    done

    # Compute exp(x - max) for each
    local -a exps=()
    local sum=0
    for ((i=0; i<n; i++)); do
        local shifted=$((logits[i] - max))
        local e=$(fp_exp "$shifted")
        exps+=("$e")
        sum=$((sum + e))
    done

    # Normalize
    local -a probs=()
    for ((i=0; i<n; i++)); do
        if [[ $sum -gt 0 ]]; then
            probs+=("$(( (exps[i] * SCALE) / sum ))")
        else
            probs+=("$((SCALE / n))")
        fi
    done

    echo "${probs[*]}"
}

# Argmax of array
# Returns index of maximum value
fp_argmax() {
    local -a vals=($1)
    local max_idx=0
    local max_val="${vals[0]}"

    for ((i=1; i<${#vals[@]}; i++)); do
        if [[ ${vals[i]} -gt $max_val ]]; then
            max_val=${vals[i]}
            max_idx=$i
        fi
    done

    echo "$max_idx"
}

# Sample from probability distribution
# Takes probabilities and returns sampled index
fp_sample() {
    local -a probs=($1)
    local temperature="${2:-$SCALE}"  # Default temperature 1.0

    # If temperature is 0, just argmax
    if [[ $temperature -eq 0 ]]; then
        fp_argmax "$1"
        return
    fi

    # Generate random threshold in [0, SCALE)
    local threshold=$(( RANDOM * SCALE / 32768 ))

    # Cumulative sum to find bucket
    local cumsum=0
    for ((i=0; i<${#probs[@]}; i++)); do
        cumsum=$((cumsum + probs[i]))
        if [[ $cumsum -gt $threshold ]]; then
            echo "$i"
            return
        fi
    done

    # Fallback: return last index
    echo "$((${#probs[@]} - 1))"
}

# Self-test
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== Fixed-Point Math Library Tests ==="
    echo

    echo "Conversions:"
    echo "  1.5 -> $(fp_from_float 1.5) (expect 15000)"
    echo "  15000 -> $(fp_to_float 15000) (expect 1.5000)"
    echo "  -0.25 -> $(fp_from_float -0.25) (expect -2500)"
    echo

    echo "Basic arithmetic:"
    echo "  1.5 * 2.0 = $(fp_to_float $(fp_mul 15000 20000)) (expect 3.0)"
    echo "  3.0 / 2.0 = $(fp_to_float $(fp_div 30000 20000)) (expect 1.5)"
    echo

    echo "Square root:"
    echo "  sqrt(4.0) = $(fp_to_float $(fp_sqrt 40000)) (expect 2.0)"
    echo "  sqrt(2.0) = $(fp_to_float $(fp_sqrt 20000)) (expect ~1.414)"
    echo

    echo "Exponential:"
    echo "  exp(1.0) = $(fp_to_float $(fp_exp 10000)) (expect ~2.7183)"
    echo "  exp(0.0) = $(fp_to_float $(fp_exp 0)) (expect 1.0)"
    echo

    echo "Tanh:"
    echo "  tanh(1.0) = $(fp_to_float $(fp_tanh 10000)) (expect ~0.7616)"
    echo "  tanh(0.0) = $(fp_to_float $(fp_tanh 0)) (expect 0.0)"
    echo

    echo "GELU:"
    echo "  gelu(1.0) = $(fp_to_float $(fp_gelu 10000)) (expect ~0.841)"
    echo "  gelu(-1.0) = $(fp_to_float $(fp_gelu -10000)) (expect ~-0.159)"
    echo

    echo "Softmax:"
    echo "  softmax([1, 2, 3]) = $(fp_softmax "10000 20000 30000")"
    echo "  (expect roughly: 0.09, 0.24, 0.67 scaled)"
    echo

    echo "=== Tests Complete ==="
fi
