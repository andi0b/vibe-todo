#!/bin/bash
# Frontend Service - Serves HTML/CSS/JS
# Listens on port 8003

PORT="${PORT:-8003}"

html_page() {
cat << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bash Todo App</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>⭐</text></svg>">
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Source Code Pro', monospace;
            background: #0f0f23;
            color: #cccccc;
            min-height: 100vh;
            padding: 40px 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: #10101a;
            border: 1px solid #333340;
            box-shadow: 0 0 20px rgba(0, 153, 0, 0.1);
        }
        .ascii-header {
            background: #0f0f23;
            padding: 20px;
            text-align: center;
            border-bottom: 1px solid #333340;
            white-space: pre;
            font-size: 10px;
            line-height: 1.2;
            color: #00cc00;
        }
        header {
            background: #10101a;
            color: #cccccc;
            padding: 20px;
            text-align: center;
            border-bottom: 1px solid #333340;
        }
        header h1 {
            font-size: 24px;
            color: #00cc00;
            text-shadow: 0 0 5px #00cc00;
        }
        header p {
            color: #666666;
            font-size: 12px;
            margin-top: 8px;
        }
        header .stars {
            color: #ffff66;
            font-size: 14px;
            margin-top: 5px;
        }
        .add-form {
            display: flex;
            padding: 15px;
            gap: 10px;
            border-bottom: 1px solid #333340;
            background: #0f0f23;
        }
        .add-form input {
            flex: 1;
            padding: 10px 12px;
            border: 1px solid #333340;
            background: #10101a;
            color: #cccccc;
            font-family: 'Source Code Pro', monospace;
            font-size: 14px;
        }
        .add-form input::placeholder { color: #666666; }
        .add-form input:focus {
            outline: none;
            border-color: #00cc00;
            box-shadow: 0 0 5px rgba(0, 204, 0, 0.3);
        }
        .add-form button {
            padding: 10px 20px;
            background: #0f0f23;
            color: #00cc00;
            border: 1px solid #00cc00;
            font-family: 'Source Code Pro', monospace;
            font-size: 14px;
            cursor: pointer;
            transition: all 0.2s;
        }
        .add-form button:hover {
            background: #00cc00;
            color: #0f0f23;
            text-shadow: none;
        }
        .todo-list {
            list-style: none;
            max-height: 400px;
            overflow-y: auto;
        }
        .todo-list::-webkit-scrollbar { width: 8px; }
        .todo-list::-webkit-scrollbar-track { background: #10101a; }
        .todo-list::-webkit-scrollbar-thumb { background: #333340; }
        .todo-item {
            display: flex;
            align-items: center;
            padding: 12px 15px;
            border-bottom: 1px solid #1a1a2e;
            transition: background 0.2s;
        }
        .todo-item:hover { background: #1a1a2e; }
        .todo-item.done .text {
            color: #666666;
        }
        .checkbox {
            width: 20px;
            height: 20px;
            margin-right: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 16px;
            color: #333340;
        }
        .todo-item .checkbox::before { content: '○'; }
        .todo-item.done .checkbox::before { content: '★'; color: #ffff66; }
        .text { flex: 1; font-size: 14px; }
        .delete {
            background: none;
            border: none;
            color: #ff6666;
            cursor: pointer;
            font-size: 16px;
            opacity: 0;
            font-family: 'Source Code Pro', monospace;
            transition: opacity 0.2s;
        }
        .todo-item:hover .delete { opacity: 1; }
        .delete:hover { color: #ff9999; }
        .empty {
            text-align: center;
            padding: 40px;
            color: #666666;
            font-style: italic;
        }
        .empty::before {
            content: '>';
            color: #00cc00;
            margin-right: 8px;
        }
        .stats {
            padding: 12px 15px;
            background: #0f0f23;
            font-size: 12px;
            color: #666666;
            text-align: center;
            border-top: 1px solid #333340;
        }
        .stats .completed { color: #ffff66; }
        .arch {
            text-align: center;
            padding: 10px;
            background: #10101a;
            font-size: 10px;
            color: #333340;
            border-top: 1px solid #1a1a2e;
        }
        .arch span { color: #009900; }
        .blink { animation: blink 1s step-end infinite; }
        @keyframes blink { 50% { opacity: 0; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="ascii-header">
 _               _       _            _
| |__   __ _ ___| |__   | |_ ___   __| | ___
| '_ \ / _` / __| '_ \  | __/ _ \ / _` |/ _ \
| |_) | (_| \__ \ | | | | || (_) | (_| | (_) |
|_.__/ \__,_|___/_| |_|  \__\___/ \__,_|\___/
        </div>
        <header>
            <h1>--- Day ?: Todo List ---</h1>
            <p>// microservices in pure bash. no npm. no sanity.</p>
            <div class="stars" id="stars"></div>
        </header>
        <form class="add-form" onsubmit="add(event)">
            <input type="text" id="input" placeholder="> enter todo item..." autofocus>
            <button type="submit">[ADD]</button>
        </form>
        <ul class="todo-list" id="list"></ul>
        <div class="stats" id="stats"></div>
        <div class="arch"><span>gateway</span>:8000 → <span>todo</span>:8002 → <span>storage</span>:8001 | <span>frontend</span>:8003</div>
    </div>
    <script>
        const API = '/api/todos';
        async function load() {
            try {
                const r = await fetch(API);
                const todos = await r.json();
                const list = document.getElementById('list');
                const stats = document.getElementById('stats');
                const stars = document.getElementById('stars');
                const completed = todos.filter(t => t.completed).length;
                const total = todos.length;

                // Update stars display (AoC style)
                if (total > 0) {
                    const goldStars = '★'.repeat(completed);
                    const grayStars = '☆'.repeat(total - completed);
                    stars.innerHTML = goldStars + '<span style="color:#333340">' + grayStars + '</span>';
                } else {
                    stars.textContent = '';
                }

                if (!todos.length) {
                    list.innerHTML = '<li class="empty">no todos yet. the terminal awaits...</li>';
                    stats.textContent = '';
                    return;
                }
                list.innerHTML = todos.map(t =>
                    '<li class="todo-item' + (t.completed ? ' done' : '') + '">' +
                    '<div class="checkbox" onclick="toggle(' + t.id + ')"></div>' +
                    '<span class="text">' + esc(t.title) + '</span>' +
                    '<button class="delete" onclick="del(' + t.id + ')">[x]</button>' +
                    '</li>'
                ).join('');
                stats.innerHTML = '<span class="completed">' + completed + '</span> of ' + total + ' completed // ' + (total - completed) + ' remaining';
            } catch(e) { console.error('Load failed:', e); }
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

respond() {
    local status="$1" ctype="$2" body="$3"
    local byte_len=$(printf '%s' "$body" | wc -c)
    printf "HTTP/1.1 %s\r\n" "$status"
    printf "Content-Type: %s\r\n" "$ctype"
    printf "Content-Length: %d\r\n" "$byte_len"
    printf "Connection: close\r\n"
    printf "\r\n%s" "$body"
}

handle() {
    local line method path

    read -r line || return
    [[ -z "$line" ]] && return

    method="${line%% *}"
    path="${line#* }"; path="${path%% *}"

    # Consume headers
    while IFS= read -r header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break
    done

    case "$path" in
        /|/index.html) respond "200 OK" "text/html" "$(html_page)" ;;
        /health) respond "200 OK" "application/json" '{"status":"ok","service":"frontend"}' ;;
        *) respond "404 Not Found" "text/plain" "Not Found" ;;
    esac
}

serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}

echo "Frontend Service on port $PORT"
trap "exit 0" INT TERM

while true; do serve; done
