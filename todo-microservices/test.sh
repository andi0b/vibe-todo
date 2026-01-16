#!/bin/bash
# Test script for the Bash Todo Microservices
# Runs against the gateway on port 8000

PORT="${TEST_PORT:-8000}"

echo "=== BASH TODO MICROSERVICES TEST ==="
echo "Testing against port $PORT"
echo ""

echo "1. Health check (gateway):"
printf 'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "2. Add first todo:"
printf 'POST /api/todos HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 20\r\n\r\n{"title":"Buy milk"}' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "3. Add second todo:"
printf 'POST /api/todos HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 24\r\n\r\n{"title":"Walk the dog"}' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "4. Get all todos:"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "5. Mark first todo complete (PATCH):"
printf 'PATCH /api/todos/1 HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 18\r\n\r\n{"completed":true}' | nc -w2 localhost "$PORT" | head -n 1
echo ""

echo "6. Get todos (after marking complete):"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "7. Mark first todo incomplete (PATCH):"
printf 'PATCH /api/todos/1 HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 19\r\n\r\n{"completed":false}' | nc -w2 localhost "$PORT" | head -n 1
echo ""

echo "8. Get todos (after marking incomplete):"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "9. Delete second todo:"
printf 'DELETE /api/todos/2 HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "10. Final todos:"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost "$PORT" | tail -n 1
echo ""

echo "=== ALL TESTS COMPLETE ==="
