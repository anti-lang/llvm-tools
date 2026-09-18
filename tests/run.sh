#!/bin/sh
# Run every test under tests/ and report each one.
cd "$(dirname "$0")" || exit 1
failed=0
for test in test-*.sh; do
    if sh "$test"; then
        printf 'pass %s\n' "$test"
    else
        printf 'FAIL %s\n' "$test"
        failed=1
    fi
done
exit "$failed"
