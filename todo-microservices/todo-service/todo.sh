#!/bin/bash
# Todo Service - Business logic for todo operations
# Listens on port 8002, uses Storage Service on 8001

PORT=8002
STORAGE_HOST="localhost"
STORAGE_PORT=8001

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

get_todos() { storage_call "GET" "/todos"; }
get_next_id() { storage_call "GET" "/nextid" | grep -oE '[0-9]+' | head -1; }
save_todos() { storage_call "POST" "/todos" "$1" >/dev/null; }

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

toggle_todo() {
    local id="$1"
    local todos=$(get_todos)

    if printf '%s' "$todos" | grep -q "\"id\":$id,.*\"completed\":false"; then
        todos=$(printf '%s' "$todos" | sed "s/\(\"id\":$id,[^}]*\"completed\":\)false/\1true/")
    else
        todos=$(printf '%s' "$todos" | sed "s/\(\"id\":$id,[^}]*\"completed\":\)true/\1false/")
    fi

    save_todos "$todos"
    printf '{"status":"toggled"}'
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
            elif [[ "$path" =~ ^/todos/([0-9]+)/toggle$ ]]; then
                status="200 OK"; body_out=$(toggle_todo "${BASH_REMATCH[1]}")
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

    printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n%s" \
        "$status" "${#body_out}" "$body_out"
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "Todo Service on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
