#!/bin/bash
# Start all microservices for the Bash Todo App

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS=()

echo "======================================"
echo "   Bash Todo - Microservices Stack"
echo "======================================"
echo ""

cleanup() {
    echo ""
    echo "Shutting down services..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    done
    pkill -f "nc -l -p 800" 2>/dev/null
    echo "All services stopped."
    exit 0
}
trap cleanup EXIT INT TERM

start_service() {
    local name="$1"
    local script="$2"

    echo "Starting $name..."
    bash "$script" &
    PIDS+=($!)
    sleep 0.3
}

# Reset data
echo '[]' > "$BASE_DIR/data/todos.json"

# Start services in order
start_service "Storage Service (port 8001)" "$BASE_DIR/storage-service/storage.sh"
start_service "Todo Service (port 8002)" "$BASE_DIR/todo-service/todo.sh"
start_service "Frontend Service (port 8003)" "$BASE_DIR/frontend-service/frontend.sh"
start_service "API Gateway (port 8000)" "$BASE_DIR/api-gateway/gateway.sh"

echo ""
echo "======================================"
echo "   All services started!"
echo "======================================"
echo ""
echo "Open http://localhost:8000 in your browser"
echo ""
echo "Architecture:"
echo "  Browser → Gateway:8000 → Todo:8002 → Storage:8001"
echo "                       ↘ Frontend:8003"
echo ""
echo "Health endpoints:"
echo "  curl localhost:8000/health  # Gateway"
echo "  curl localhost:8001/health  # Storage"
echo "  curl localhost:8002/health  # Todo"
echo "  curl localhost:8003/health  # Frontend"
echo ""
echo "Press Ctrl+C to stop all services"
echo ""

wait
