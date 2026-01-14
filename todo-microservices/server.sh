#!/bin/bash
# Unified Todo Server - Single bash script serving both API and frontend
# Port 8080

PORT=8080
DATA_DIR="/mnt/d/git/github/vibe-todo/todo-microservices/data"
TODOS_FILE="$DATA_DIR/todos.json"

mkdir -p "$DATA_DIR"
[[ ! -f "$TODOS_FILE" ]] && echo '[]' > "$TODOS_FILE"

# Generate next todo ID
next_id() {
    local max=$(grep -oE '"id":[0-9]+' "$TODOS_FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
    echo $((${max:-0}+1))
}

# Get all todos
get_todos() {
    cat "$TODOS_FILE"
}

# Add a todo (with file locking)
add_todo() {
    local title="$1"
    (
        flock -x 200
        local id=$(next_id)
        local new="{\"id\":$id,\"title\":\"$title\",\"completed\":false}"
        local todos=$(cat "$TODOS_FILE")

        if [[ "$todos" == "[]" ]]; then
            echo "[$new]" > "$TODOS_FILE"
        else
            echo "${todos%]},$new]" > "$TODOS_FILE"
        fi
        echo "$new"
    ) 200>"$TODOS_FILE.lock"
}

# Toggle todo (with file locking)
toggle_todo() {
    local id="$1"
    (
        flock -x 200
        local todos=$(cat "$TODOS_FILE")

        if echo "$todos" | grep -q "\"id\":$id,.*\"completed\":false"; then
            todos=$(echo "$todos" | sed "s/\(\"id\":$id,[^}]*\"completed\":\)false/\1true/")
        else
            todos=$(echo "$todos" | sed "s/\(\"id\":$id,[^}]*\"completed\":\)true/\1false/")
        fi

        echo "$todos" > "$TODOS_FILE"
        echo '{"status":"toggled"}'
    ) 200>"$TODOS_FILE.lock"
}

# Delete todo (with file locking)
delete_todo() {
    local id="$1"
    (
        flock -x 200
        local todos=$(cat "$TODOS_FILE")
        todos=$(echo "$todos" | sed "s/{\"id\":$id,\"title\":\"[^\"]*\",\"completed\":[^}]*},\?//g" | sed 's/,]/]/g' | sed 's/\[,/[/g')
        echo "$todos" > "$TODOS_FILE"
        echo '{"status":"deleted"}'
    ) 200>"$TODOS_FILE.lock"
}

# HTML Frontend
html_page() {
cat << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bash Todo App</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: system-ui, sans-serif; background: linear-gradient(135deg, #667eea, #764ba2); min-height: 100vh; padding: 40px 20px; }
        .container { max-width: 500px; margin: 0 auto; background: #fff; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); overflow: hidden; }
        header { background: #667eea; color: #fff; padding: 30px; text-align: center; }
        header h1 { font-size: 28px; }
        header p { opacity: 0.8; font-size: 14px; margin-top: 5px; }
        .add-form { display: flex; padding: 20px; gap: 10px; border-bottom: 1px solid #eee; }
        .add-form input { flex: 1; padding: 12px 16px; border: 2px solid #e0e0e0; border-radius: 8px; font-size: 16px; }
        .add-form input:focus { outline: none; border-color: #667eea; }
        .add-form button { padding: 12px 24px; background: #667eea; color: #fff; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; }
        .add-form button:hover { background: #5a6fd6; }
        .todo-list { list-style: none; max-height: 400px; overflow-y: auto; }
        .todo-item { display: flex; align-items: center; padding: 16px 20px; border-bottom: 1px solid #f0f0f0; }
        .todo-item:hover { background: #f9f9f9; }
        .todo-item.done .text { text-decoration: line-through; color: #aaa; }
        .checkbox { width: 24px; height: 24px; border: 2px solid #ddd; border-radius: 50%; margin-right: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; }
        .todo-item.done .checkbox { background: #667eea; border-color: #667eea; }
        .todo-item.done .checkbox::after { content: '\2713'; color: #fff; font-size: 14px; }
        .text { flex: 1; font-size: 16px; }
        .delete { background: none; border: none; color: #ff6b6b; cursor: pointer; font-size: 20px; opacity: 0; }
        .todo-item:hover .delete { opacity: 1; }
        .empty { text-align: center; padding: 60px; color: #aaa; }
        .stats { padding: 16px 20px; background: #f9f9f9; font-size: 14px; color: #666; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <header><h1>Bash Todo</h1><p>Powered by shell scripts</p></header>
        <form class="add-form" onsubmit="add(event)">
            <input type="text" id="input" placeholder="What needs to be done?" autofocus>
            <button type="submit">Add</button>
        </form>
        <ul class="todo-list" id="list"></ul>
        <div class="stats" id="stats"></div>
    </div>
    <script>
        const API = '/api/todos';
        async function load() {
            const r = await fetch(API);
            const todos = await r.json();
            const list = document.getElementById('list');
            const stats = document.getElementById('stats');
            if (!todos.length) {
                list.innerHTML = '<li class="empty">No todos yet!</li>';
                stats.textContent = '';
                return;
            }
            list.innerHTML = todos.map(t =>
                '<li class="todo-item' + (t.completed ? ' done' : '') + '" data-id="' + t.id + '">' +
                '<div class="checkbox" onclick="toggle(' + t.id + ')"></div>' +
                '<span class="text">' + esc(t.title) + '</span>' +
                '<button class="delete" onclick="del(' + t.id + ')">×</button>' +
                '</li>'
            ).join('');
            stats.textContent = todos.filter(t => t.completed).length + ' of ' + todos.length + ' completed';
        }
        function esc(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
        async function add(e) {
            e.preventDefault();
            const i = document.getElementById('input');
            if (!i.value.trim()) return;
            await fetch(API, { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({title: i.value.trim()}) });
            i.value = '';
            load();
        }
        async function toggle(id) { await fetch(API + '/' + id + '/toggle', { method: 'POST' }); load(); }
        async function del(id) { await fetch(API + '/' + id, { method: 'DELETE' }); load(); }
        load();
    </script>
</body>
</html>
HTMLEOF
}

# Send response
respond() {
    local status="$1" ctype="$2" body="$3"
    printf "HTTP/1.1 %s\r\n" "$status"
    printf "Content-Type: %s\r\n" "$ctype"
    printf "Content-Length: %d\r\n" "${#body}"
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
    printf "Access-Control-Allow-Headers: Content-Type\r\n"
    printf "Connection: close\r\n"
    printf "\r\n%s" "$body"
}

# Handle request
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

    # Route
    case "$method $path" in
        "OPTIONS "*) respond "200 OK" "text/plain" "" ;;
        "GET /"|"GET /index.html") respond "200 OK" "text/html" "$(html_page)" ;;
        "GET /api/todos") respond "200 OK" "application/json" "$(get_todos)" ;;
        "POST /api/todos")
            local title=$(echo "$body" | sed 's/.*"title":"\([^"]*\)".*/\1/')
            if [[ -n "$title" && "$title" != "$body" ]]; then
                respond "201 Created" "application/json" "$(add_todo "$title")"
            else
                respond "400 Bad Request" "application/json" '{"error":"title required"}'
            fi ;;
        "POST /api/todos/"*"/toggle")
            local id=$(echo "$path" | grep -oE '/todos/([0-9]+)/' | grep -oE '[0-9]+')
            respond "200 OK" "application/json" "$(toggle_todo "$id")" ;;
        "DELETE /api/todos/"*)
            local id=$(echo "$path" | grep -oE '[0-9]+')
            respond "200 OK" "application/json" "$(delete_todo "$id")" ;;
        "GET /health") respond "200 OK" "application/json" '{"status":"ok"}' ;;
        *) respond "404 Not Found" "application/json" '{"error":"not found"}' ;;
    esac
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "Todo Server running on http://localhost:$PORT"
echo "Press Ctrl+C to stop"

trap "echo 'Shutting down...'; exit 0" INT TERM

while true; do
    serve
done
