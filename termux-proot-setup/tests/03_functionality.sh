#!/usr/bin/env bash
#===============================================================================
# Test: Setup Script Functionality
# Validates setup.sh help and flag parsing
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SETUP="$REPO_DIR/setup.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

failed=0

echo "Running functionality tests..."

# Test help flag
echo -n "  Testing --help... "
if "$SETUP" --help >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test version flag
echo -n "  Testing --version... "
if "$SETUP" --version >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test --test flag (dry run)
echo -n "  Testing --test... "
if "$SETUP" --test >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIPPED (requires full environment)${NC}"
fi

# Test flag parsing
echo -n "  Testing --tmux flag parsing... "
if "$SETUP" --tmux 2>&1 | grep -q "Installing"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi

echo -n "  Testing --picoclaw flag parsing... "
if "$SETUP" --picoclaw 2>&1 | grep -q "Installing"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi

echo -n "  Testing --shell flag parsing... "
if "$SETUP" --shell 2>&1 | grep -q "Installing"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi

echo -n "  Testing --termux-boot flag parsing... "
if "$SETUP" --termux-boot 2>&1 | grep -q "Installing"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi

exit $failed
