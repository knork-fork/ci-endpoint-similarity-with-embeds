#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
FIXTURES_DIR="$SCRIPT_DIR/Fixtures"

total=0
passed=0
failed=0
failed_tests=()

# Failing tests
for file in "$FIXTURES_DIR"/Failing/*.php; do
    total=$((total + 1))
    filename=$(basename "$file")

    # We expect test_similarity.sh to return failure (non-zero) for every fixture
    if ! bash "$SCRIPT_DIR/test_similarity.sh" "$file" > /dev/null 2>&1; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_tests+=("$filename")
    fi
done

# Passing tests
for file in "$FIXTURES_DIR"/Passing/*.php; do
    total=$((total + 1))
    filename=$(basename "$file")

    # We expect test_similarity.sh to return success (zero) for every fixture
    if bash "$SCRIPT_DIR/test_similarity.sh" "$file" > /dev/null 2>&1; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_tests+=("$filename")
    fi
done

echo "Total: $total | Passed: $passed | Failed: $failed"

if [[ $failed -gt 0 ]]; then
    for t in "${failed_tests[@]}"; do
        echo "  FAIL: $t (expected failure but got OK)"
    done
    exit 1
fi
