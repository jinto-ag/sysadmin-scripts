#!/usr/bin/env bash
#===============================================================================
# Test Runner
# Runs all tests in the tests directory
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

total=0
passed=0
failed=0

echo "========================================"
echo "Running All Tests"
echo "========================================"
echo ""

for test in "$SCRIPT_DIR"/*.sh; do
    if [ -f "$test" ] && [ -x "$test" ]; then
        name=$(basename "$test")
        if [ "$name" = "run.sh" ]; then
            continue
        fi
        
        ((total++))
        echo "----------------------------------------"
        echo "Running: $name"
        echo "----------------------------------------"
        
        if "$test"; then
            ((passed++))
            echo -e "${GREEN}✓ $name PASSED${NC}"
        else
            ((failed++))
            echo -e "${RED}✗ $name FAILED${NC}"
        fi
        echo ""
    fi
done

echo "========================================"
echo "Results: $passed/$total passed, $failed failed"
echo "========================================"

if [ $failed -gt 0 ]; then
    exit 1
fi
exit 0
