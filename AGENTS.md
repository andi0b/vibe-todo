# AGENTS.md

> Technical briefing for AI agents. Read SOUL.md first for the voice. This doc is the rules.

## Golden Rules

1. **No external dependencies.** No `npm`, no `pip`, no `jq`. We parse JSON with `sed` and `grep` like our ancestors intended. The only dependencies are bash, netcat, and audacity.

2. **Over-engineering is the feature.** If your solution seems too simple, add another microservice. This is the way.

3. **Tests must pass.** Run `./test.sh` before committing. We're chaotic, not incompetent.

4. **Commit messages are performances.** "Fixed bug" is forbidden. Make it dramatic. Make it funny. The diff explains the what; the message explains the drama.

5. **Keep it working.** Absurd? Yes. Broken? Never.

## Project Structure

```
vibe-todo/
├── todo-microservices/
│   ├── api-gateway/gateway.sh    # Port 8000 - Routes requests, serves frontend
│   ├── frontend-service/frontend.sh  # Port 8003 - Serves HTML/CSS/JS
│   ├── todo-service/todo.sh      # Port 8002 - Business logic
│   ├── storage-service/storage.sh    # Port 8001 - File persistence
│   ├── data/todos.json           # The "database"
│   ├── start.sh                  # Starts all microservices
│   ├── stop.sh                   # Kills the dream
│   ├── test.sh                   # Proves we're not animals
│   └── server.sh                 # Monolith version (port 8080)
```

## Running the Project

```bash
cd todo-microservices
./start.sh          # Start microservices stack
./stop.sh           # Stop all services
./test.sh           # Run tests
./server.sh         # Alternative: single monolith on port 8080
```

## Request Flow

```
Browser :8000 → Gateway → Frontend Service :8003 (for HTML)
Browser :8000 → Gateway → Todo Service :8002 → Storage Service :8001 (for API)
```

## Critical Technical Details

### HTTP in Bash: The \r\n Trap

HTTP uses `\r\n` line endings. When parsing responses with `sed`:
- `^$` does NOT match the blank line (it contains `\r`)
- Use `^\r*$` or strip carriage returns first
- This has caused bugs. It will cause bugs again. Stay vigilant.

### The netcat Pattern

Each service uses this pattern:
```bash
serve() {
    coproc NC { nc -l -p "$PORT"; }
    handle <&"${NC[0]}" >&"${NC[1]}"
    exec {NC[0]}>&- {NC[1]}>&- 2>/dev/null
    wait $NC_PID 2>/dev/null
}
while true; do serve; done
```

This handles one connection at a time. It's not concurrent. It's not fast. It's beautiful.

### JSON "Parsing"

We use `sed`, `grep`, and `awk` to parse JSON. There's no `jq`. Examples from the codebase:
- Extract field: `grep -o '"id":[0-9]*' | cut -d: -f2`
- Build JSON: `printf '{"id":%d,"title":"%s"}' "$id" "$title"`

If you add JSON handling, follow this pattern. Suffer with us.

### File Locking

Storage service uses `flock` for concurrent access:
```bash
flock -x 200
# ... do stuff ...
) 200>"$LOCK_FILE"
```

Always use locking when touching `todos.json`.

## Common Tasks

### Adding a New Endpoint

1. Add route in `gateway.sh` case statement
2. Add handler in appropriate service
3. Update test.sh with new test case
4. Write a sarcastic commit message

### Adding a New Service

1. Create `service-name/service.sh` following existing patterns
2. Add to `start.sh` startup sequence
3. Add to `stop.sh` kill patterns
4. Add health check endpoint
5. Update architecture diagrams in README.md
6. Question your life choices
7. Continue anyway

### Modifying the Frontend

The entire frontend is embedded in `frontend-service/frontend.sh` as a heredoc. Yes, really. HTML, CSS, and JavaScript all in one bash script. The `html_page()` function returns it all.

## Testing

Run `./test.sh` before committing. It tests:
- All health endpoints
- CRUD operations on todos
- API response formats

If tests fail, fix them. We may be chaotic but we're not *that* chaotic.

## Code Style

- Use `local` for function variables
- Use `[[ ]]` for conditionals (we're not POSIX purists)
- Use `printf` over `echo` for anything with special characters
- Heredocs for multi-line strings
- Comments only when the bash is truly cursed (which is often)

## Debugging

Services print to stdout. Check the terminal where `start.sh` is running.

Test individual services:
```bash
curl localhost:8000/health  # Gateway
curl localhost:8001/health  # Storage
curl localhost:8002/health  # Todo
curl localhost:8003/health  # Frontend
```

