#!/bin/bash
# Stop all microservices
# "Chaos, but controlled chaos"

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$BASE_DIR/.pids"

echo "Stopping all Todo microservices..."

# Method 1: Use PID files if they exist (preferred - clean shutdown)
if [[ -d "$PID_DIR" ]]; then
    for pidfile in "$PID_DIR"/*.pid; do
        [[ -f "$pidfile" ]] || continue
        service=$(basename "$pidfile" .pid)
        pid=$(cat "$pidfile" 2>/dev/null)
        if [[ -n "$pid" ]]; then
            echo "  Stopping $service (PID: $pid)..."
            # Try to kill the process group first, fall back to just the pid
            kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        fi
        rm -f "$pidfile"
    done
    rm -rf "$PID_DIR"
    echo "  Waiting for graceful shutdown..."
    sleep 1
fi

# Method 2: Find and kill bash service processes by their script names
echo "  Cleaning up any remaining service processes..."
for service in storage.sh bashis.sh todo.sh frontend.sh llm.sh gateway.sh; do
    pkill -TERM -f "bash.*$service" 2>/dev/null
done

# Method 3: Kill nc processes on our ports (fallback)
for port in 8000 8001 8002 8003 8004 6379; do
    # Use fuser if available, otherwise try lsof
    if command -v fuser &>/dev/null; then
        fuser -k -TERM "$port/tcp" 2>/dev/null
    elif command -v lsof &>/dev/null; then
        pid=$(lsof -ti :"$port" 2>/dev/null)
        [[ -n "$pid" ]] && kill -TERM $pid 2>/dev/null
    fi
done

# Give things a moment to die gracefully
sleep 0.5

# Method 4: Force kill anything still running on our ports
echo "  Force killing any stubborn processes..."
pkill -9 -f "nc -l -p 800[0-4]" 2>/dev/null
pkill -9 -f "nc -l -p 6379" 2>/dev/null

# Clean up pipes
rm -f /tmp/storage_pipe_* /tmp/todo_pipe_* /tmp/gateway_pipe_* /tmp/frontend_pipe_* /tmp/bashis_pipe_* /tmp/llm_pipe_* 2>/dev/null

echo "All services stopped."
