#!/bin/bash
# Storage Service - Handles file-based persistence for todos
# Listens on port 8001

PORT="${PORT:-8001}"
DATA_DIR="${DATA_DIR:-/data}"
TODOS_FILE="$DATA_DIR/todos.json"

mkdir -p "$DATA_DIR"
[[ ! -f "$TODOS_FILE" ]] && echo '[]' > "$TODOS_FILE"

handle() {
    local line method path len=0 body="" status body_out

    read -r -t 5 line || return
    [[ -z "$line" ]] && return
    line="${line%$'\r'}"

    method="${line%% *}"
    path="${line#* }"; path="${path%% *}"

    while IFS= read -r -t 2 header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break
        [[ "$header" =~ Content-Length:\ *([0-9]+) ]] && len="${BASH_REMATCH[1]}"
    done

    if [[ $len -gt 0 ]]; then
        read -r -t 10 -n "$len" body
        read -r -t 0.1 _ 2>/dev/null || true
    fi

    case "$method $path" in
        "GET /todos")
            status="200 OK"; body_out=$(cat "$TODOS_FILE") ;;
        "POST /todos")
            printf '%s' "$body" > "$TODOS_FILE"
            status="200 OK"; body_out='{"ok":true}' ;;
        "GET /nextid")
            local max=$(grep -oE '"id":[0-9]+' "$TODOS_FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
            status="200 OK"; body_out="{\"id\":$((${max:-0}+1))}" ;;
        "GET /health")
            status="200 OK"; body_out='{"status":"ok","service":"storage"}' ;;
        *)
            status="404 Not Found"; body_out='{"error":"not found"}' ;;
    esac

    local byte_len=$(printf '%s' "$body_out" | wc -c)
    printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s" \
        "$status" "$byte_len" "$body_out"
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    local nc_pid=$!
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    kill "$nc_pid" 2>/dev/null
    wait "$nc_pid" 2>/dev/null
}

echo "Storage Service on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
