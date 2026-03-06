#!/usr/bin/env bash
#===============================================================================
# Test: Configuration File Validation
# Validates JSON config files and templates
#===============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

failed=0

echo "Running configuration validation tests..."

# Test picoclaw config template
echo -n "  Checking picoclaw config.json.template... "
if [ -f "$REPO_DIR/config/picoclaw/config.json.template" ]; then
    if jq empty "$REPO_DIR/config/picoclaw/config.json.template" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED (invalid JSON)${NC}"
        failed=1
    fi
else
    echo -e "${YELLOW}SKIPPED (not found)${NC}"
fi

# Test shell templates exist
echo -n "  Checking zshenv.template... "
if [ -f "$REPO_DIR/config/shell/zshenv.template" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

echo -n "  Checking zshrc.template... "
if [ -f "$REPO_DIR/config/shell/zshrc.template" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

echo -n "  Checking profile.template... "
if [ -f "$REPO_DIR/config/shell/profile.template" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test tmux config
echo -n "  Checking tmux.conf... "
if [ -f "$REPO_DIR/config/tmux/tmux.conf" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

# Test termux boot scripts
echo -n "  Checking tmux-start.sh... "
if [ -f "$REPO_DIR/config/termux-boot/tmux-start.sh" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

echo -n "  Checking tmux-sessions.sh... "
if [ -f "$REPO_DIR/config/termux-boot/tmux-sessions.sh" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    failed=1
fi

exit $failed
