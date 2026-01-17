#!/bin/bash
# LLM Service - A transformer inference engine in AWK (wrapped in bash)
# Listens on port 8004
# "We trained the model in PyTorch, wrote inference in bash, then rewrote it in AWK for speed"
# "The architects have left the building"

PORT="${PORT:-8004}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MODEL_DIR="${MODEL_DIR:-$SCRIPT_DIR/model}"

# Source the AWK-powered transformer (the bash libs still exist for the math functions)
source "$SCRIPT_DIR/lib/awk_forward.sh"

# Model state
MODEL_LOADED=0

# Try to load the model on startup
load_model_if_exists() {
    if [[ -f "$MODEL_DIR/config.txt" ]]; then
        echo "Found model at $MODEL_DIR, loading..." >&2
        if init_model "$MODEL_DIR"; then
            MODEL_LOADED=1
            echo "Model loaded successfully!" >&2
        else
            echo "Failed to load model" >&2
        fi
    else
        echo "No model found at $MODEL_DIR" >&2
        echo "Run ./init_model.sh to create a random model for testing" >&2
    fi
}

# Extract JSON field value (our cursed JSON parser)
# Now handles colons in values because Shakespeare apparently uses them
json_get() {
    local json="$1"
    local field="$2"

    # For string values: match "field":"value" or "field": "value"
    # Use a more specific pattern that handles colons in values
    local result
    result=$(echo "$json" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1)
    if [[ -n "$result" ]]; then
        # Extract just the value part (after first colon, strip quotes)
        echo "$result" | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
        return
    fi

    # For numeric values: match "field": 123 or "field":123
    result=$(echo "$json" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*[0-9]+" | head -1)
    if [[ -n "$result" ]]; then
        echo "$result" | sed 's/^[^:]*:[[:space:]]*//'
        return
    fi
}

# Build JSON response
json_response() {
    local status="$1"
    local message="$2"
    printf '{"status":"%s","message":"%s"}' "$status" "$message"
}

handle() {
    local line method path len=0 body="" status body_out content_type="application/json"

    # Read with timeout to prevent hanging
    read -r -t 5 line || return
    [[ -z "$line" ]] && return

    # Strip carriage return
    line="${line%$'\r'}"

    method="${line%% *}"
    path="${line#* }"; path="${path%% *}"

    # Read headers with timeout
    while IFS= read -r -t 2 header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break
        [[ "$header" =~ Content-Length:\ *([0-9]+) ]] && len="${BASH_REMATCH[1]}"
    done

    # Read body if present (with timeout)
    if [[ $len -gt 0 ]]; then
        read -r -t 30 -n "$len" body
        # Drain any trailing newlines/whitespace
        read -r -t 0.1 _ 2>/dev/null || true
    fi

    case "$method $path" in
        "GET /health")
            status="200 OK"
            if [[ $MODEL_LOADED -eq 1 ]]; then
                body_out='{"status":"ok","service":"llm","model":"loaded","config":{"n_embd":'$N_EMBD',"n_layer":'$N_LAYER',"n_head":'$N_HEAD'}}'
            else
                body_out='{"status":"ok","service":"llm","model":"not_loaded"}'
            fi
            ;;

        "POST /generate")
            if [[ $MODEL_LOADED -eq 0 ]]; then
                status="503 Service Unavailable"
                body_out='{"error":"model not loaded","hint":"run init_model.sh first"}'
            else
                # Parse request
                local prompt=$(json_get "$body" "prompt")
                local max_tokens=$(json_get "$body" "max_tokens")
                local temperature=$(json_get "$body" "temperature")

                # Defaults
                [[ -z "$prompt" ]] && prompt="Hello"
                [[ -z "$max_tokens" ]] && max_tokens=10
                [[ -z "$temperature" ]] && temperature="10000"  # 1.0 in fixed-point

                # Sanity limits (we're in bash, let's not get crazy)
                [[ $max_tokens -gt 50 ]] && max_tokens=50

                echo "Generate request: prompt='$prompt', max_tokens=$max_tokens, temp=$temperature" >&2

                # Generate!
                local start_time=$(date +%s)
                local generated=$(generate "$prompt" "$max_tokens" "$temperature")
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))

                # Escape the output for JSON
                generated=$(printf '%s' "$generated" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g')

                status="200 OK"
                body_out=$(printf '{"generated":"%s","tokens":%d,"time_seconds":%d,"warning":"this is bash inference, time is a feature not a bug"}' \
                    "$generated" "$max_tokens" "$duration")
            fi
            ;;

        "POST /tokenize")
            # Convert text to token IDs (for debugging)
            local text=$(json_get "$body" "text")
            local -a tokens=()

            for ((i=0; i<${#text}; i++)); do
                local char="${text:i:1}"
                tokens+=("$(printf '%d' "'$char")")
            done

            status="200 OK"
            body_out=$(printf '{"tokens":[%s],"length":%d}' \
                "$(IFS=,; echo "${tokens[*]}")" "${#tokens[@]}")
            ;;

        "POST /detokenize")
            # Convert token IDs back to text (for debugging)
            local tokens_str=$(json_get "$body" "tokens")
            # Parse the array (cursed but it works)
            tokens_str=$(echo "$tokens_str" | tr -d '[]' | tr ',' ' ')

            local text=""
            for tok in $tokens_str; do
                if [[ $tok -ge 32 && $tok -le 126 ]]; then
                    text="${text}$(printf "\\$(printf '%03o' "$tok")")"
                else
                    text="${text}?"
                fi
            done

            status="200 OK"
            body_out=$(printf '{"text":"%s"}' "$text")
            ;;

        "GET /config")
            if [[ $MODEL_LOADED -eq 1 ]]; then
                status="200 OK"
                body_out=$(printf '{"n_embd":%d,"n_head":%d,"n_layer":%d,"vocab_size":%d,"block_size":%d,"head_dim":%d}' \
                    "$N_EMBD" "$N_HEAD" "$N_LAYER" "$VOCAB_SIZE" "$BLOCK_SIZE" "$HEAD_DIM")
            else
                status="503 Service Unavailable"
                body_out='{"error":"model not loaded"}'
            fi
            ;;

        "POST /reload")
            # Reload the model (useful after init_model.sh)
            MODEL_LOADED=0
            load_model_if_exists
            if [[ $MODEL_LOADED -eq 1 ]]; then
                status="200 OK"
                body_out='{"status":"reloaded"}'
            else
                status="503 Service Unavailable"
                body_out='{"error":"failed to reload model"}'
            fi
            ;;

        "OPTIONS "*)
            # CORS preflight
            status="204 No Content"
            body_out=""
            ;;

        *)
            status="404 Not Found"
            body_out='{"error":"not found","endpoints":["/health","/generate","/tokenize","/detokenize","/config","/reload"]}'
            ;;
    esac

    local byte_len=$(printf '%s' "$body_out" | wc -c)
    printf "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n%s" \
        "$status" "$content_type" "$byte_len" "$body_out"
}

serve() {
    # Start netcat listener as a coprocess
    coproc NC { nc -l -p "$PORT"; }
    local nc_pid=$!

    # Handle the request
    handle <&"${NC[0]}" >&"${NC[1]}"

    # Clean up: close file descriptors and wait for nc to exit
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null

    # Kill the nc process if it's still running (prevents zombie connections)
    kill "$nc_pid" 2>/dev/null
    wait "$nc_pid" 2>/dev/null
}

# Startup
echo "=========================================="
echo " LLM Service - AWK Transformer Edition"
echo " (bash for orchestration, AWK for math)"
echo "=========================================="
echo
echo "Listening on port $PORT"
echo "Model directory: $MODEL_DIR"
echo

load_model_if_exists

echo
echo "Endpoints:"
echo "  GET  /health      - Service health check"
echo "  POST /generate    - Generate text (body: {\"prompt\": \"...\", \"max_tokens\": N})"
echo "  POST /tokenize    - Convert text to tokens"
echo "  POST /detokenize  - Convert tokens to text"
echo "  GET  /config      - Model configuration"
echo "  POST /reload      - Reload model from disk"
echo
echo "Ready for inference. AWK-powered = faster than pure bash. Still absurd."
echo

trap "exit 0" INT TERM

while true; do serve; done
