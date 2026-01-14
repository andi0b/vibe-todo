#!/bin/bash
# Test script for the Bash Todo Server

echo "=== BASH TODO SERVER TEST ==="
echo ""

echo "1. Health check:"
printf 'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "2. Add first todo:"
printf 'POST /api/todos HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 20\r\n\r\n{"title":"Buy milk"}' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "3. Add second todo:"
printf 'POST /api/todos HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 24\r\n\r\n{"title":"Walk the dog"}' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "4. Get all todos:"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "5. Toggle first todo:"
printf 'POST /api/todos/1/toggle HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "6. Get todos (after toggle):"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "7. Delete second todo:"
printf 'DELETE /api/todos/2 HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "8. Final todos:"
printf 'GET /api/todos HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc -w2 localhost 8080 | tail -n 1
echo ""

echo "=== ALL TESTS COMPLETE ==="
