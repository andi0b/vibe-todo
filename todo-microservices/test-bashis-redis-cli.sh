#!/bin/bash
# Test Bashis using actual redis-cli to prove Redis compatibility
# Requires redis-cli to be installed (apt install redis-tools)

PORT="${BASHIS_PORT:-6379}"

# Check if redis-cli is available
if ! command -v redis-cli &>/dev/null; then
    echo "=== BASHIS REDIS-CLI COMPATIBILITY TEST ==="
    echo ""
    echo "SKIPPED: redis-cli not found"
    echo "Install with: apt install redis-tools"
    echo ""
    exit 0
fi

echo "=== BASHIS REDIS-CLI COMPATIBILITY TEST ==="
echo "Testing Bashis on port $PORT with actual redis-cli"
echo "This proves our bash Redis clone speaks real RESP protocol!"
echo ""

PASS=0
FAIL=0

# Test helper - with small delay to let Bashis restart its listener
test_cmd() {
    local name="$1"
    local expected="$2"
    shift 2
    local result

    sleep 0.2  # Give Bashis time to restart nc listener between connections
    result=$(redis-cli -p "$PORT" "$@" 2>/dev/null)

    if [[ "$result" == "$expected" ]]; then
        echo "✓ $name"
        ((PASS++))
    else
        echo "✗ $name"
        echo "  Expected: $expected"
        echo "  Got:      $result"
        ((FAIL++))
    fi
}

# Test helper for pattern matching
test_cmd_match() {
    local name="$1"
    local pattern="$2"
    shift 2
    local result

    result=$(redis-cli -p "$PORT" "$@" 2>/dev/null)

    if [[ "$result" =~ $pattern ]]; then
        echo "✓ $name"
        ((PASS++))
    else
        echo "✗ $name"
        echo "  Expected pattern: $pattern"
        echo "  Got: $result"
        ((FAIL++))
    fi
}

# First, flush the database to start clean
echo "--- Setup ---"
sleep 0.3
redis-cli -p "$PORT" FLUSHDB >/dev/null 2>&1
sleep 0.2

echo ""
echo "--- PING Test ---"
test_cmd "PING returns PONG" "PONG" PING

echo ""
echo "--- SET/GET Tests ---"
test_cmd "SET greeting hello" "OK" SET greeting "hello"
test_cmd "GET greeting" "hello" GET greeting
test_cmd "SET counter 42" "OK" SET counter "42"
test_cmd "GET counter" "42" GET counter

echo ""
echo "--- GET non-existent key ---"
test_cmd "GET nonexistent returns nil" "" GET nonexistent

echo ""
echo "--- DBSIZE Test ---"
test_cmd "DBSIZE shows 2 keys" "2" DBSIZE

echo ""
echo "--- EXISTS Tests ---"
test_cmd "EXISTS greeting (1 key)" "1" EXISTS greeting
test_cmd "EXISTS greeting counter (2 keys)" "2" EXISTS greeting counter
test_cmd "EXISTS greeting counter nonexistent (2 found)" "2" EXISTS greeting counter nonexistent
test_cmd "EXISTS nonexistent (0 keys)" "0" EXISTS nonexistent

echo ""
echo "--- KEYS Test ---"
# KEYS returns results in arbitrary order, so just check we get results
sleep 0.2
result=$(redis-cli -p "$PORT" KEYS '*' 2>/dev/null | wc -l)
if [[ "$result" -eq 2 ]]; then
    echo "✓ KEYS '*' returns 2 keys"
    ((PASS++))
else
    echo "✗ KEYS '*' returns 2 keys (got $result)"
    ((FAIL++))
fi

echo ""
echo "--- DEL Tests ---"
test_cmd "DEL greeting (1 deleted)" "1" DEL greeting
test_cmd "GET greeting after DEL" "" GET greeting
test_cmd "DEL nonexistent (0 deleted)" "0" DEL nonexistent

echo ""
echo "--- Multiple DEL ---"
sleep 0.2; redis-cli -p "$PORT" SET a 1 >/dev/null
sleep 0.2; redis-cli -p "$PORT" SET b 2 >/dev/null
sleep 0.2; redis-cli -p "$PORT" SET c 3 >/dev/null
test_cmd "DEL a b c (3 deleted)" "3" DEL a b c

echo ""
echo "--- FLUSHDB Test ---"
sleep 0.2; redis-cli -p "$PORT" SET test1 "value1" >/dev/null
sleep 0.2; redis-cli -p "$PORT" SET test2 "value2" >/dev/null
test_cmd "FLUSHDB" "OK" FLUSHDB
test_cmd "DBSIZE after FLUSHDB" "0" DBSIZE

echo ""
echo "--- Values with spaces ---"
test_cmd "SET with spaces" "OK" SET message "hello world"
test_cmd "GET with spaces" "hello world" GET message

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "All tests passed! Bashis speaks Redis!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
