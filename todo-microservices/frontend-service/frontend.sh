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
    <title>bash todo</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>⭐</text></svg>">
    <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --ctp-base: #24273a;
            --ctp-mantle: #1e2030;
            --ctp-crust: #181926;
            --ctp-text: #cad3f5;
            --ctp-subtext0: #a5adcb;
            --ctp-subtext1: #b8c0e0;
            --ctp-surface0: #363a4f;
            --ctp-surface1: #494d64;
            --ctp-surface2: #5b6078;
            --ctp-overlay0: #6e738d;
            --ctp-green: #a6da95;
            --ctp-yellow: #eed49f;
            --ctp-red: #ed8796;
            --ctp-mauve: #c6a0f6;
            --ctp-lavender: #b7bdf8;
            --ctp-teal: #8bd5ca;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Source Code Pro', monospace;
            background: var(--ctp-crust);
            min-height: 100vh;
            padding: 40px 20px;
            color: var(--ctp-text);
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: var(--ctp-base);
            border: 1px solid var(--ctp-surface1);
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.4);
        }
        header {
            padding: 24px;
            text-align: center;
            border-bottom: 1px solid var(--ctp-surface0);
        }
        .ascii-title {
            color: var(--ctp-green);
            font-size: 11px;
            line-height: 1.2;
            white-space: pre;
            margin-bottom: 8px;
        }
        header p {
            color: var(--ctp-subtext0);
            font-size: 12px;
        }
        header p span { color: var(--ctp-yellow); }
        .add-form {
            display: flex;
            padding: 16px;
            gap: 8px;
            border-bottom: 1px solid var(--ctp-surface0);
            background: var(--ctp-mantle);
        }
        .add-form .prompt {
            color: var(--ctp-green);
            font-size: 16px;
            line-height: 42px;
        }
        .add-form input {
            flex: 1;
            padding: 10px 12px;
            background: var(--ctp-surface0);
            border: 1px solid var(--ctp-surface1);
            border-radius: 4px;
            font-size: 14px;
            font-family: 'Source Code Pro', monospace;
            color: var(--ctp-text);
        }
        .add-form input::placeholder { color: var(--ctp-overlay0); }
        .add-form input:focus {
            outline: none;
            border-color: var(--ctp-mauve);
            box-shadow: 0 0 0 2px rgba(198, 160, 246, 0.2);
        }
        .add-form button {
            padding: 10px 16px;
            background: var(--ctp-surface1);
            color: var(--ctp-green);
            border: 1px solid var(--ctp-surface2);
            border-radius: 4px;
            font-size: 14px;
            font-family: 'Source Code Pro', monospace;
            cursor: pointer;
            transition: all 0.15s;
        }
        .add-form button:hover {
            background: var(--ctp-surface2);
            border-color: var(--ctp-green);
        }
        .todo-list { list-style: none; max-height: 400px; overflow-y: auto; }
        .todo-item {
            display: flex;
            align-items: center;
            padding: 12px 16px;
            border-bottom: 1px solid var(--ctp-surface0);
            transition: background 0.1s;
        }
        .todo-item:hover { background: var(--ctp-mantle); }
        .todo-item.done .text {
            text-decoration: line-through;
            color: var(--ctp-overlay0);
        }
        .checkbox {
            width: 20px;
            height: 20px;
            border: 2px solid var(--ctp-surface2);
            border-radius: 4px;
            margin-right: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 12px;
            transition: all 0.15s;
        }
        .checkbox:hover { border-color: var(--ctp-mauve); }
        .todo-item.done .checkbox {
            background: var(--ctp-green);
            border-color: var(--ctp-green);
            color: var(--ctp-crust);
        }
        .todo-item.done .checkbox::after { content: '★'; }
        .text { flex: 1; font-size: 14px; color: var(--ctp-text); }
        .delete {
            background: none;
            border: none;
            color: var(--ctp-surface2);
            cursor: pointer;
            font-size: 14px;
            font-family: 'Source Code Pro', monospace;
            opacity: 0;
            padding: 4px 8px;
            transition: all 0.15s;
        }
        .delete:hover { color: var(--ctp-red); }
        .todo-item:hover .delete { opacity: 1; }
        .empty {
            text-align: center;
            padding: 48px;
            color: var(--ctp-subtext0);
            font-style: italic;
        }
        .stats {
            padding: 12px 16px;
            background: var(--ctp-mantle);
            font-size: 12px;
            color: var(--ctp-subtext0);
            text-align: center;
            border-top: 1px solid var(--ctp-surface0);
        }
        .stats .count { color: var(--ctp-yellow); }
        .arch {
            text-align: center;
            padding: 12px;
            background: var(--ctp-crust);
            font-size: 11px;
            color: var(--ctp-overlay0);
            border-top: 1px solid var(--ctp-surface0);
            border-radius: 0 0 8px 8px;
        }
        .arch span { color: var(--ctp-teal); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <pre class="ascii-title"> _               _       _            _
| |__   __ _ ___| |__   | |_ ___   __| | ___
| '_ \ / _` / __| '_ \  | __/ _ \ / _` |/ _ \
| |_) | (_| \__ \ | | | | || (_) | (_| | (_) |
|_.__/ \__,_|___/_| |_|  \__\___/ \__,_|\___/ </pre>
            <p>// microservices in pure bash. <span>no npm. no sanity.</span></p>
        </header>
        <form class="add-form" onsubmit="add(event)">
            <span class="prompt">&gt;</span>
            <input type="text" id="input" placeholder="what needs to be done?" autofocus>
            <button type="submit">[add]</button>
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
                const done = todos.filter(t => t.completed).length;
                stats.innerHTML = '<span class="count">' + done + '</span> of <span class="count">' + todos.length + '</span> completed' + (done > 0 ? ' ★'.repeat(Math.min(done, 5)) : '');
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
