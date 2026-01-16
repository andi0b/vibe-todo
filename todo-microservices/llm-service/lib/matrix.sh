#!/bin/bash
# Matrix Operations Library for Bash LLM
# Row-major storage because column-major is for FORTRAN programmers

_MATRIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MATRIX_LIB_DIR/math.sh"

# Matrices are stored as space-separated values in row-major order
# Dimensions are tracked separately (we're not going to be clever about this)

# Matrix-vector multiplication
# Usage: mat_vec_mul "1 2 3 4 5 6" 2 3 "1 1 1" -> "6 15"
# (2x3 matrix) * (3-vector) = (2-vector)
mat_vec_mul() {
    local -a mat=($1)
    local rows="$2"
    local cols="$3"
    local -a vec=($4)
    local -a result=()

    for ((i=0; i<rows; i++)); do
        local sum=0
        for ((j=0; j<cols; j++)); do
            local m_idx=$((i * cols + j))
            sum=$(( sum + (mat[m_idx] * vec[j]) / SCALE ))
        done
        result+=("$sum")
    done

    echo "${result[*]}"
}

# Matrix-matrix multiplication
# Usage: mat_mul "1 2 3 4" 2 2 "5 6 7 8" 2 2 -> "19 22 43 50"
# A[m,k] * B[k,n] = C[m,n]
mat_mul() {
    local -a A=($1)
    local m="$2"
    local k="$3"
    local -a B=($4)
    local k2="$5"
    local n="$6"
    local -a C=()

    [[ $k -ne $k2 ]] && { echo "ERROR: dimension mismatch" >&2; return 1; }

    for ((i=0; i<m; i++)); do
        for ((j=0; j<n; j++)); do
            local sum=0
            for ((l=0; l<k; l++)); do
                local a_idx=$((i * k + l))
                local b_idx=$((l * n + j))
                sum=$(( sum + (A[a_idx] * B[b_idx]) / SCALE ))
            done
            C+=("$sum")
        done
    done

    echo "${C[*]}"
}

# Transpose matrix
# Usage: mat_transpose "1 2 3 4 5 6" 2 3 -> "1 4 2 5 3 6"
mat_transpose() {
    local -a mat=($1)
    local rows="$2"
    local cols="$3"
    local -a result=()

    for ((j=0; j<cols; j++)); do
        for ((i=0; i<rows; i++)); do
            local idx=$((i * cols + j))
            result+=("${mat[idx]}")
        done
    done

    echo "${result[*]}"
}

# Element-wise addition of two vectors/matrices
vec_add() {
    local -a a=($1)
    local -a b=($2)
    local -a result=()

    for ((i=0; i<${#a[@]}; i++)); do
        result+=("$((a[i] + b[i]))")
    done

    echo "${result[*]}"
}

# Element-wise subtraction
vec_sub() {
    local -a a=($1)
    local -a b=($2)
    local -a result=()

    for ((i=0; i<${#a[@]}; i++)); do
        result+=("$((a[i] - b[i]))")
    done

    echo "${result[*]}"
}

# Element-wise multiplication (Hadamard product)
vec_mul() {
    local -a a=($1)
    local -a b=($2)
    local -a result=()

    for ((i=0; i<${#a[@]}; i++)); do
        result+=("$(( (a[i] * b[i]) / SCALE ))")
    done

    echo "${result[*]}"
}

# Scalar multiplication
vec_scale() {
    local -a vec=($1)
    local scalar="$2"
    local -a result=()

    for ((i=0; i<${#vec[@]}; i++)); do
        result+=("$(( (vec[i] * scalar) / SCALE ))")
    done

    echo "${result[*]}"
}

# Dot product of two vectors
vec_dot() {
    local -a a=($1)
    local -a b=($2)
    local sum=0

    for ((i=0; i<${#a[@]}; i++)); do
        sum=$(( sum + (a[i] * b[i]) / SCALE ))
    done

    echo "$sum"
}

# L2 norm of vector
vec_norm() {
    local -a vec=($1)
    local sum_sq=0

    for val in "${vec[@]}"; do
        sum_sq=$(( sum_sq + (val * val) / SCALE ))
    done

    fp_sqrt "$sum_sq"
}

# Apply function to each element
# Usage: vec_apply "gelu" "1000 2000 3000"
vec_apply() {
    local func="$1"
    local -a vec=($2)
    local -a result=()

    for val in "${vec[@]}"; do
        case "$func" in
            gelu)  result+=("$(fp_gelu "$val")") ;;
            tanh)  result+=("$(fp_tanh "$val")") ;;
            exp)   result+=("$(fp_exp "$val")") ;;
            sqrt)  result+=("$(fp_sqrt "$val")") ;;
            *)     result+=("$val") ;;
        esac
    done

    echo "${result[*]}"
}

# Layer normalization
# Usage: layer_norm "1000 2000 3000" "10000 10000 10000" "0 0 0" -> normalized
# vec, gamma (weight), beta (bias)
layer_norm() {
    local -a vec=($1)
    local -a gamma=($2)
    local -a beta=($3)
    local eps="${4:-100}"  # epsilon = 0.01 default
    local n=${#vec[@]}

    # Compute mean
    local sum=0
    for val in "${vec[@]}"; do
        sum=$((sum + val))
    done
    local mean=$((sum / n))

    # Compute variance
    local var_sum=0
    for val in "${vec[@]}"; do
        local diff=$((val - mean))
        var_sum=$(( var_sum + (diff * diff) / SCALE ))
    done
    local variance=$((var_sum / n))

    # Standard deviation (sqrt(variance + eps))
    local std=$(fp_sqrt $((variance + eps)))
    [[ $std -lt 100 ]] && std=100  # Prevent division by tiny numbers

    # Normalize: (x - mean) / std * gamma + beta
    local -a result=()
    for ((i=0; i<n; i++)); do
        local normalized=$(( ((vec[i] - mean) * SCALE) / std ))
        local scaled=$(( (normalized * gamma[i]) / SCALE ))
        result+=("$((scaled + beta[i]))")
    done

    echo "${result[*]}"
}

# RMS normalization (used in Llama-style models)
rms_norm() {
    local -a vec=($1)
    local -a gamma=($2)
    local eps="${3:-100}"
    local n=${#vec[@]}

    # Compute mean of squares
    local sum_sq=0
    for val in "${vec[@]}"; do
        sum_sq=$(( sum_sq + (val * val) / SCALE ))
    done
    local ms=$((sum_sq / n))

    # RMS = sqrt(mean_square + eps)
    local rms=$(fp_sqrt $((ms + eps)))
    [[ $rms -lt 100 ]] && rms=100

    # Normalize: x / rms * gamma
    local -a result=()
    for ((i=0; i<n; i++)); do
        local normalized=$(( (vec[i] * SCALE) / rms ))
        result+=("$(( (normalized * gamma[i]) / SCALE ))")
    done

    echo "${result[*]}"
}

# Initialize random matrix
# Usage: mat_random_init rows cols scale -> space-separated random values
mat_random_init() {
    local rows="$1"
    local cols="$2"
    local limit="${3:-1000}"  # Default: [-0.1, 0.1]
    local -a result=()

    for ((i=0; i<rows*cols; i++)); do
        result+=("$(fp_random "$limit")")
    done

    echo "${result[*]}"
}

# Initialize zeros
mat_zeros() {
    local rows="$1"
    local cols="$2"
    local -a result=()

    for ((i=0; i<rows*cols; i++)); do
        result+=(0)
    done

    echo "${result[*]}"
}

# Initialize ones (in fixed-point: SCALE)
mat_ones() {
    local rows="$1"
    local cols="$2"
    local -a result=()

    for ((i=0; i<rows*cols; i++)); do
        result+=("$SCALE")
    done

    echo "${result[*]}"
}

# Get row from matrix
mat_get_row() {
    local -a mat=($1)
    local cols="$2"
    local row_idx="$3"
    local start=$((row_idx * cols))

    echo "${mat[*]:$start:$cols}"
}

# Get column from matrix (inefficient but sometimes needed)
mat_get_col() {
    local -a mat=($1)
    local rows="$2"
    local cols="$3"
    local col_idx="$4"
    local -a result=()

    for ((i=0; i<rows; i++)); do
        local idx=$((i * cols + col_idx))
        result+=("${mat[idx]}")
    done

    echo "${result[*]}"
}

# Slice vector
vec_slice() {
    local -a vec=($1)
    local start="$2"
    local length="$3"

    echo "${vec[*]:$start:$length}"
}

# Concatenate vectors
vec_concat() {
    local result=""
    for vec in "$@"; do
        result="$result $vec"
    done
    echo "${result# }"
}

# Reshape (just changes how we interpret the data, returns same array)
# This is a no-op for row-major storage but documents intent
mat_reshape() {
    echo "$1"  # Data doesn't change, just interpretation
}

# Print matrix in human-readable format
mat_print() {
    local -a mat=($1)
    local rows="$2"
    local cols="$3"

    for ((i=0; i<rows; i++)); do
        local row=""
        for ((j=0; j<cols; j++)); do
            local idx=$((i * cols + j))
            row="$row $(fp_to_float "${mat[idx]}")"
        done
        echo " $row"
    done
}

# Self-test
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_matrix_tests() {
        echo "=== Matrix Operations Tests ==="
        echo

        echo "Matrix-vector multiplication:"
        # [[1, 2, 3], [4, 5, 6]] * [1, 1, 1] = [6, 15]
        local m1="10000 20000 30000 40000 50000 60000"  # 2x3 matrix, scaled
        local v1="10000 10000 10000"  # [1, 1, 1] scaled
        local r1=$(mat_vec_mul "$m1" 2 3 "$v1")
        echo "  [[1,2,3],[4,5,6]] * [1,1,1] = $r1"
        echo "  As floats: $(fp_to_float ${r1%% *}), $(fp_to_float ${r1##* })"
        echo "  (expect 6, 15)"
        echo

        echo "Matrix multiplication:"
        # [[1, 2], [3, 4]] * [[5, 6], [7, 8]] = [[19, 22], [43, 50]]
        local A="10000 20000 30000 40000"  # 2x2
        local B="50000 60000 70000 80000"  # 2x2
        local C=$(mat_mul "$A" 2 2 "$B" 2 2)
        echo "  2x2 matmul result: $C"
        echo "  As matrix:"
        mat_print "$C" 2 2
        echo "  (expect [[19,22],[43,50]])"
        echo

        echo "Transpose:"
        local t1="10000 20000 30000 40000 50000 60000"  # 2x3
        local t2=$(mat_transpose "$t1" 2 3)
        echo "  [[1,2,3],[4,5,6]] transposed:"
        mat_print "$t2" 3 2
        echo "  (expect [[1,4],[2,5],[3,6]])"
        echo

        echo "Layer normalization:"
        local ln_in="10000 20000 30000"  # [1, 2, 3]
        local ln_g="10000 10000 10000"   # gamma = [1, 1, 1]
        local ln_b="0 0 0"               # beta = [0, 0, 0]
        local ln_out=$(layer_norm "$ln_in" "$ln_g" "$ln_b")
        echo "  LayerNorm([1,2,3]): $ln_out"
        echo "  As floats: $(echo $ln_out | tr ' ' '\n' | while read v; do fp_to_float "$v"; echo -n " "; done)"
        echo "  (expect roughly: -1.22, 0, 1.22)"
        echo

        echo "Dot product:"
        local dp=$(vec_dot "10000 20000 30000" "10000 10000 10000")
        echo "  [1,2,3] · [1,1,1] = $(fp_to_float $dp) (expect 6)"
        echo

        echo "=== Tests Complete ==="
    }
    run_matrix_tests
fi
