#!/bin/bash
# Stop all microservices

echo "Stopping all Todo microservices..."

# Kill processes on our ports
fuser -k 8000/tcp 2>/dev/null
fuser -k 8001/tcp 2>/dev/null
fuser -k 8002/tcp 2>/dev/null
fuser -k 8003/tcp 2>/dev/null
fuser -k 8004/tcp 2>/dev/null
fuser -k 6379/tcp 2>/dev/null

# Clean up pipes
rm -f /tmp/storage_pipe_* /tmp/todo_pipe_* /tmp/gateway_pipe_* /tmp/frontend_pipe_* /tmp/bashis_pipe_* /tmp/llm_pipe_*

echo "All services stopped."
