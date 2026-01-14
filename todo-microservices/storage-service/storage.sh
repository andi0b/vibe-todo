#!/bin/bash
# Storage Service - Handles file-based persistence for todos
# Listens on port 8001

PORT=8001
DATA_DIR="/mnt/d/git/github/vibe-todo/todo-microservices/data"
TODOS_FILE="$DATA_DIR/todos.json"

mkdir -p "$DATA_DIR"
[[ ! -f "$TODOS_FILE" ]] && echo '[]' > "$TODOS_FILE"

handle() {
    local line method path len=0 body="" status body_out

    read -r line || return
    [[ -z "$line" ]] && return

    method="${line%% *}"
    path="${line#* }"; path="${path%% *}"

    while IFS= read -r header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break
        [[ "$header" =~ Content-Length:\ *([0-9]+) ]] && len="${BASH_REMATCH[1]}"
    done

    [[ $len -gt 0 ]] && read -r -n "$len" body

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

    printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s" \
        "$status" "${#body_out}" "$body_out"
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "Storage Service on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
