#!/usr/bin/env bash
#===============================================================================
# Test: Syntax Validation
# Validates that all shell scripts have valid bash syntax
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

failed=0

echo "Running syntax validation tests..."

# Test setup.sh
echo -n "  Checking setup.sh... "
if bash -n "$REPO_DIR/setup.sh" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test config scripts
for script in "$REPO_DIR"/config/picoclaw/scripts/*.sh; do
    if [ -f "$script" ]; then
        name=$(basename "$script")
        echo -n "  Checking $name... "
        if bash -n "$script" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            failed=1
        fi
    fi
done

# Test tmux session launcher
echo -n "  Checking session-launcher.sh... "
if bash -n "$REPO_DIR/config/tmux/session-launcher.sh" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test termux boot scripts
for script in "$REPO_DIR/config/termux-boot/*.sh"; do
    if [ -f "$script" ]; then
        name=$(basename "$script")
        echo -n "  Checking $name... "
        if bash -n "$script" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            failed=1
        fi
    fi
done

exit $failed
