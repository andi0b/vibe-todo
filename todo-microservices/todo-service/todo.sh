#!/bin/bash
# Todo Service - Business logic for todo operations
# Listens on port 8002, uses Storage Service on 8001

PORT="${PORT:-8002}"
STORAGE_HOST="${STORAGE_HOST:-localhost}"
STORAGE_PORT="${STORAGE_PORT:-8001}"
BASHIS_HOST="${BASHIS_HOST:-localhost}"
BASHIS_PORT="${BASHIS_PORT:-6379}"

# Call storage service and return response body
storage_call() {
    local method="$1" path="$2" body="$3"
    local response

    if [[ -n "$body" ]]; then
        response=$(printf "%s %s HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n\r\n%s" \
            "$method" "$path" "$STORAGE_HOST" "${#body}" "$body" | nc -w2 "$STORAGE_HOST" "$STORAGE_PORT" 2>/dev/null)
    else
        response=$(printf "%s %s HTTP/1.1\r\nHost: %s\r\n\r\n" \
            "$method" "$path" "$STORAGE_HOST" | nc -w2 "$STORAGE_HOST" "$STORAGE_PORT" 2>/dev/null)
    fi
    # Return body (last line)
    printf '%s\n' "$response" | tail -1
}

# Bashis (cache) helpers - speak RESP protocol like civilized software
bashis_call() {
    local cmd="$1"
    shift
    local args=("$@")
    local resp=""

    # Build RESP array: *N\r\n$len\r\narg\r\n...
    local count=$((1 + ${#args[@]}))
    resp="*${count}\r\n"
    resp+="\$${#cmd}\r\n${cmd}\r\n"
    for arg in "${args[@]}"; do
        resp+="\$${#arg}\r\n${arg}\r\n"
    done

    # Send to Bashis and get response
    printf '%b' "$resp" | nc -w1 "$BASHIS_HOST" "$BASHIS_PORT" 2>/dev/null
}

cache_get() {
    local key="$1"
    local response
    response=$(bashis_call "GET" "$key")
    # Parse RESP bulk string response: $len\r\ndata\r\n or $-1\r\n for nil
    if [[ "$response" =~ ^\$-1 ]]; then
        return 1  # Cache miss
    elif [[ "$response" =~ ^\$([0-9]+) ]]; then
        # Extract the data after $len\r\n
        printf '%s' "$response" | sed -n '2p' | tr -d '\r'
        return 0
    fi
    return 1
}

cache_set() {
    local key="$1" value="$2"
    bashis_call "SET" "$key" "$value" >/dev/null 2>&1
}

cache_del() {
    local key="$1"
    bashis_call "DEL" "$key" >/dev/null 2>&1
}

get_todos() {
    # Try cache first
    local cached
    if cached=$(cache_get "todos:all"); then
        printf '%s' "$cached"
        return
    fi
    # Cache miss - fetch from storage and cache it
    local todos
    todos=$(storage_call "GET" "/todos")
    cache_set "todos:all" "$todos"
    printf '%s' "$todos"
}
get_next_id() { storage_call "GET" "/nextid" | grep -oE '[0-9]+' | head -1; }
save_todos() {
    storage_call "POST" "/todos" "$1" >/dev/null
    # Invalidate cache after write
    cache_del "todos:all"
}

add_todo() {
    local title="$1"
    local todos=$(get_todos)
    local next_id=$(get_next_id)
    local new_todo="{\"id\":$next_id,\"title\":\"$title\",\"completed\":false}"

    if [[ "$todos" == "[]" ]]; then
        todos="[$new_todo]"
    else
        todos="${todos%]},${new_todo}]"
    fi

    save_todos "$todos"
    printf '%s' "$new_todo"
}

set_todo_completed() {
    local id="$1" completed="$2"
    local todos=$(get_todos)
    # No greedy .* nonsense - just set the state directly like a civilized service
    todos=$(printf '%s' "$todos" | sed "s/\(\"id\":$id,[^}]*\"completed\":\)\(true\|false\)/\1$completed/")
    save_todos "$todos"
}

delete_todo() {
    local id="$1"
    local todos=$(get_todos)
    todos=$(printf '%s' "$todos" | sed "s/{\"id\":$id,\"title\":\"[^\"]*\",\"completed\":[^}]*},\?//g" | sed 's/,]/]/g' | sed 's/\[,/[/g')
    save_todos "$todos"
    printf '{"status":"deleted"}'
}

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

    local id=""
    [[ "$path" =~ ^/todos/([0-9]+) ]] && id="${BASH_REMATCH[1]}"

    case "$method" in
        OPTIONS) status="200 OK"; body_out="" ;;
        GET)
            case "$path" in
                /todos) status="200 OK"; body_out=$(get_todos) ;;
                /health) status="200 OK"; body_out='{"status":"ok","service":"todo"}' ;;
                *) status="404 Not Found"; body_out='{"error":"not found"}' ;;
            esac ;;
        POST)
            if [[ "$path" == "/todos" ]]; then
                local title=$(printf '%s' "$body" | sed 's/.*"title":"\([^"]*\)".*/\1/')
                if [[ -n "$title" && "$title" != "$body" ]]; then
                    status="201 Created"; body_out=$(add_todo "$title")
                else
                    status="400 Bad Request"; body_out='{"error":"title required"}'
                fi
            else
                status="404 Not Found"; body_out='{"error":"not found"}'
            fi ;;
        PATCH)
            if [[ "$path" =~ ^/todos/([0-9]+)$ ]]; then
                local completed=$(printf '%s' "$body" | sed 's/.*"completed":\(true\|false\).*/\1/')
                if [[ "$completed" == "true" || "$completed" == "false" ]]; then
                    set_todo_completed "${BASH_REMATCH[1]}" "$completed"
                    status="204 No Content"; body_out=""
                else
                    status="400 Bad Request"; body_out='{"error":"completed field required (true/false)"}'
                fi
            else
                status="404 Not Found"; body_out='{"error":"not found"}'
            fi ;;
        DELETE)
            if [[ -n "$id" ]]; then
                status="200 OK"; body_out=$(delete_todo "$id")
            else
                status="400 Bad Request"; body_out='{"error":"id required"}'
            fi ;;
        *) status="405 Method Not Allowed"; body_out='{"error":"method not allowed"}' ;;
    esac

    local byte_len=$(printf '%s' "$body_out" | wc -c)
    printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n%s" \
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

echo "Todo Service on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
