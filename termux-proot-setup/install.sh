#!/usr/bin/env bash
#===============================================================================
# Termux-Proot Setup Quick Install
# Usage: curl -fsSL https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main/termux-proot-setup/install.sh | bash
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
    echo -e "${BLUE}  Termux-Proot Setup Installer v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    mkdir -p "$INSTALL_DIR"
    
    log_info "Installing Termux-Proot Setup..."
    curl -fsSL "${REPO_BASE}/termux-proot-setup/setup.sh" -o "${INSTALL_DIR}/termux-setup"
    chmod +x "${INSTALL_DIR}/termux-setup"
    
    log_success "Installed: ${INSTALL_DIR}/termux-setup"
    echo ""
    echo "Usage:"
    echo "  termux-setup --all          # Install all features"
    echo "  termux-setup --tmux         # Install tmux config"
    echo "  termux-setup --picoclaw     # Install picoclaw"
    echo "  termux-setup --shell        # Install shell config"
    echo "  termux-setup --backup       # Create backup"
    echo "  termux-setup --test         # Run tests"
    echo "  termux-setup --help          # Show help"
}

main "$@"
