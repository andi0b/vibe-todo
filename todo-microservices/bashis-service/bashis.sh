#!/bin/bash
# Bashis - A Redis clone in Bash, because real Redis is written in C, and C is for cowards
# Speaks RESP protocol on port 6379

PORT="${PORT:-6379}"

# The cache - an associative array because bash has those and we're going to use them
declare -A CACHE

# RESP protocol helpers
resp_simple() { printf '+%s\r\n' "$1"; }
resp_error() { printf '-ERR %s\r\n' "$1"; }
resp_integer() { printf ':%d\r\n' "$1"; }
resp_bulk() {
    if [[ -z "$1" && "$2" == "nil" ]]; then
        printf '$-1\r\n'
    else
        printf '$%d\r\n%s\r\n' "${#1}" "$1"
    fi
}
resp_array() {
    local count="$1"
    shift
    printf '*%d\r\n' "$count"
    for item in "$@"; do
        resp_bulk "$item"
    done
}

# Parse RESP array format: *N\r\n$len\r\narg\r\n...
parse_resp_array() {
    local line count i len arg
    RESP_ARGS=()

    # First line should be *N
    IFS= read -r line || return 1
    line="${line%$'\r'}"

    # Check for inline commands (PING, etc. without RESP framing)
    if [[ ! "$line" =~ ^\* ]]; then
        # Inline command - split by space
        line="${line%$'\r'}"
        read -ra RESP_ARGS <<< "$line"
        return 0
    fi

    count="${line#\*}"
    [[ ! "$count" =~ ^[0-9]+$ ]] && return 1

    for ((i=0; i<count; i++)); do
        IFS= read -r line || return 1
        line="${line%$'\r'}"

        if [[ "$line" =~ ^\$ ]]; then
            len="${line#\$}"
            [[ ! "$len" =~ ^[0-9]+$ ]] && return 1

            # Read exactly len bytes plus \r\n
            IFS= read -r -n "$len" arg
            RESP_ARGS+=("$arg")
            # Consume trailing \r\n
            IFS= read -r line
        else
            # Inline argument (shouldn't happen in proper RESP but handle it)
            RESP_ARGS+=("$line")
        fi
    done
    return 0
}

# Command handlers
cmd_ping() {
    if [[ -n "$1" ]]; then
        resp_bulk "$1"
    else
        resp_simple "PONG"
    fi
}

cmd_set() {
    local key="$1" value="$2"
    [[ -z "$key" ]] && { resp_error "wrong number of arguments for 'set' command"; return; }
    CACHE["$key"]="$value"
    resp_simple "OK"
}

cmd_get() {
    local key="$1"
    [[ -z "$key" ]] && { resp_error "wrong number of arguments for 'get' command"; return; }
    if [[ -v CACHE["$key"] ]]; then
        resp_bulk "${CACHE[$key]}"
    else
        resp_bulk "" "nil"
    fi
}

cmd_del() {
    local count=0 key
    for key in "$@"; do
        if [[ -v CACHE["$key"] ]]; then
            unset CACHE["$key"]
            ((count++))
        fi
    done
    resp_integer "$count"
}

cmd_exists() {
    local count=0 key
    for key in "$@"; do
        [[ -v CACHE["$key"] ]] && ((count++))
    done
    resp_integer "$count"
}

cmd_keys() {
    local pattern="${1:-*}" matches=() key
    for key in "${!CACHE[@]}"; do
        # Convert glob pattern to regex for matching
        # For simplicity, handle * and ? patterns
        local regex="${pattern//\*/.*}"
        regex="${regex//\?/.}"
        regex="^${regex}$"
        [[ "$key" =~ $regex ]] && matches+=("$key")
    done

    printf '*%d\r\n' "${#matches[@]}"
    for key in "${matches[@]}"; do
        resp_bulk "$key"
    done
}

cmd_flushdb() {
    CACHE=()
    resp_simple "OK"
}

cmd_dbsize() {
    resp_integer "${#CACHE[@]}"
}

# Handle HTTP requests (for health checks)
handle_http() {
    local line method path body len

    # Already have first line in $1
    method="${1%% *}"
    path="${1#* }"; path="${path%% *}"

    # Consume headers (read until empty line)
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && break
    done

    if [[ "$path" == "/health" ]]; then
        body='{"status":"ok","service":"bashis","keys":'${#CACHE[@]}'}'
        len=${#body}
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$len" "$body"
    else
        body='{"error":"not found"}'
        len=${#body}
        printf 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$len" "$body"
    fi
}

# Main request handler
handle() {
    local first_line cmd

    IFS= read -r first_line || return
    first_line="${first_line%$'\r'}"
    [[ -z "$first_line" ]] && return

    # Check if this is an HTTP request
    if [[ "$first_line" =~ ^(GET|POST|PUT|DELETE|HEAD|OPTIONS)\ / ]]; then
        handle_http "$first_line"
        return
    fi

    # It's RESP protocol - parse it
    RESP_ARGS=()

    if [[ "$first_line" =~ ^\* ]]; then
        # RESP array format
        local count="${first_line#\*}"
        local i len arg

        for ((i=0; i<count; i++)); do
            IFS= read -r line || return
            line="${line%$'\r'}"

            if [[ "$line" =~ ^\$ ]]; then
                len="${line#\$}"
                IFS= read -r -n "$len" arg
                RESP_ARGS+=("$arg")
                IFS= read -r line  # consume \r\n
            fi
        done
    else
        # Inline command (PING, etc.)
        read -ra RESP_ARGS <<< "$first_line"
    fi

    [[ ${#RESP_ARGS[@]} -eq 0 ]] && return

    # Extract command (uppercase it)
    cmd="${RESP_ARGS[0]^^}"

    # Dispatch command
    case "$cmd" in
        PING)    cmd_ping "${RESP_ARGS[@]:1}" ;;
        SET)     cmd_set "${RESP_ARGS[@]:1}" ;;
        GET)     cmd_get "${RESP_ARGS[@]:1}" ;;
        DEL)     cmd_del "${RESP_ARGS[@]:1}" ;;
        EXISTS)  cmd_exists "${RESP_ARGS[@]:1}" ;;
        KEYS)    cmd_keys "${RESP_ARGS[@]:1}" ;;
        FLUSHDB) cmd_flushdb ;;
        DBSIZE)  cmd_dbsize ;;
        ECHO)    resp_bulk "${RESP_ARGS[1]}" ;;
        QUIT)    resp_simple "OK" ;;
        COMMAND) resp_simple "OK" ;;  # redis-cli sends this on connect
        *)       resp_error "unknown command '$cmd'" ;;
    esac
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "Bashis (Redis clone) on port $PORT - because C is for cowards"
trap "exit 0" INT TERM

while true; do serve; done
