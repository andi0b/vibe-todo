#!/bin/bash
# API Gateway - Routes requests to microservices
# Listens on port 8000

PORT="${PORT:-8000}"
TODO_HOST="${TODO_HOST:-localhost}"
TODO_PORT="${TODO_PORT:-8002}"
FRONTEND_HOST="${FRONTEND_HOST:-localhost}"
FRONTEND_PORT="${FRONTEND_PORT:-8003}"

# Forward request to backend service
forward() {
    local host="$1" port="$2" method="$3" path="$4" body="$5"
    local response

    if [[ -n "$body" ]]; then
        response=$(printf "%s %s HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" \
            "$method" "$path" "$host" "${#body}" "$body" | nc -w5 "$host" "$port" 2>/dev/null)
    else
        response=$(printf "%s %s HTTP/1.1\r\nHost: %s\r\n\r\n" \
            "$method" "$path" "$host" | nc -w5 "$host" "$port" 2>/dev/null)
    fi
    echo "$response"
}

respond() {
    local status="$1" ctype="$2" body="$3"
    local byte_len=$(printf '%s' "$body" | wc -c)
    printf "HTTP/1.1 %s\r\n" "$status"
    printf "Content-Type: %s\r\n" "$ctype"
    printf "Content-Length: %d\r\n" "$byte_len"
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
    printf "Access-Control-Allow-Headers: Content-Type\r\n"
    printf "Connection: close\r\n"
    printf "\r\n%s" "$body"
}

handle() {
    local line method path len=0 body=""

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

    # CORS preflight
    [[ "$method" == "OPTIONS" ]] && { respond "200 OK" "text/plain" ""; return; }

    case "$path" in
        /|/index.html)
            local response=$(forward "$FRONTEND_HOST" "$FRONTEND_PORT" "GET" "/")
            local html=$(printf '%s\n' "$response" | sed '1,/^\r*$/d')
            respond "200 OK" "text/html" "$html"
            ;;
        /api/todos|/api/todos/*)
            local todo_path="${path#/api}"
            local response=$(forward "$TODO_HOST" "$TODO_PORT" "$method" "$todo_path" "$body")
            local json=$(printf '%s\n' "$response" | tail -1)
            local status=$(printf '%s\n' "$response" | head -1 | cut -d' ' -f2-3)
            respond "${status:-200 OK}" "application/json" "$json"
            ;;
        /health)
            respond "200 OK" "application/json" '{"status":"ok","service":"gateway"}'
            ;;
        *)
            respond "404 Not Found" "application/json" '{"error":"not found"}'
            ;;
    esac
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "API Gateway on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
