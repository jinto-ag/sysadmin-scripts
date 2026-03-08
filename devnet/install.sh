#!/usr/bin/env bash
#===============================================================================
# DevNet Quick Install
# Usage: curl -fsSL https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main/devnet/install.sh | bash
#===============================================================================

set -euo pipefail

VERSION="1.0.0"
INSTALL_DIR="${HOME}/.local/bin"
REPO_BASE="https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  DevNet Installer v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    mkdir -p "$INSTALL_DIR"
    
    log_info "Installing DevNet..."
    curl -fsSL "${REPO_BASE}/devnet/setup.sh" -o "${INSTALL_DIR}/devnet"
    chmod +x "${INSTALL_DIR}/devnet"
    
    log_success "Installed: ${INSTALL_DIR}/devnet"
    echo ""
    echo "Usage:"
    echo "  devnet install     # Install devnet"
    echo "  devnet status      # Show status"
    echo "  devnet --help      # Show help"
}

main "$@"
