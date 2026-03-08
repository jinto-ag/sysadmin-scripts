#!/usr/bin/env bash
#===============================================================================
# Quick Install Script for Enterprise Setup
# Usage: curl -fsSL https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main/enterprise-setup/install.sh | bash
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

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dir PATH        Install directory (default: ~/.local/bin)"
    echo "  --enterprise     Install enterprise-setup"
    echo "  --devnet         Install devnet"
    echo "  --termux-setup   Install termux-proot-setup"
    echo "  --all            Install all scripts"
    echo "  --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  # Install all"
    echo "  curl -fsSL $REPO_BASE/enterprise-setup/install.sh | bash"
    echo ""
    echo "  # Install specific script"
    echo "  curl -fsSL $REPO_BASE/enterprise-setup/install.sh | bash -s -- --enterprise"
}

install_script() {
    local script_name="$1"
    local script_path="$2"
    local install_name="${3:-$script_name}"
    
    log_info "Installing $install_name..."
    
    # Create install directory
    mkdir -p "$INSTALL_DIR"
    
    # Download script
    local url="${REPO_BASE}/${script_path}"
    if curl -fsSL "$url" -o "${INSTALL_DIR}/${install_name}"; then
        chmod +x "${INSTALL_DIR}/${install_name}"
        log_success "Installed: ${INSTALL_DIR}/${install_name}"
    else
        log_error "Failed to download $install_name"
        return 1
    fi
}

main() {
    local install_enterprise=false
    local install_devnet=false
    local install_termux=false
    local install_all=false
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --enterprise) install_enterprise=true; shift ;;
            --devnet) install_devnet=true; shift ;;
            --termux-setup) install_termux=true; shift ;;
            --all) install_all=true; shift ;;
            --help|-h) print_usage; exit 0 ;;
            *) shift ;;
        esac
    done
    
    # Default: install all if no option selected
    if [ "$install_all" = true ] || ([ "$install_enterprise" = false ] && [ "$install_devnet" = false ] && [ "$install_termux" = false ]); then
        install_enterprise=true
        install_devnet=true
        install_termux=true
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Enterprise Scripts Installer v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    log_info "Install directory: $INSTALL_DIR"
    echo ""
    
    if [ "$install_enterprise" = true ]; then
        install_script "enterprise-setup" "enterprise-setup/setup.sh" "enterprise-setup"
    fi
    
    if [ "$install_devnet" = true ]; then
        install_script "devnet" "devnet/setup.sh" "devnet"
    fi
    
    if [ "$install_termux" = true ]; then
        install_script "termux-setup" "termux-proot-setup/setup.sh" "termux-setup"
    fi
    
    echo ""
    log_success "Installation complete!"
    echo ""
    echo "Add to PATH if needed:"
    echo "  export PATH=\"\${HOME}/.local/bin:\$PATH\""
    echo ""
    echo "Usage:"
    echo "  enterprise-setup              # Run enterprise setup"
    echo "  devnet install                # Install devnet"
    echo "  termux-setup --all            # Install termux setup"
}

main "$@"
