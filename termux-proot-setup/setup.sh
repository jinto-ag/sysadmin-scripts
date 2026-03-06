#!/usr/bin/env bash
#===============================================================================
# Termux-Proot Setup - Enterprise-Grade Development Environment Setup
#===============================================================================
# Features:
#   - Interactive TUI setup
#   - Selective feature installation
#   - Backup & Restore
#   - Upgrade support
#   - Validation tests
#===============================================================================

set -euo pipefail

# Version
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${REPO_DIR}/config"
BACKUP_DIR="${HOME}/.setup-backups"
LOG_FILE="${HOME}/.setup.log"

# Feature flags (can be overridden)
FEATURE_TMUX="${FEATURE_TMUX:-1}"
FEATURE_PICOCLAW="${FEATURE_PICOCLAW:-1}"
FEATURE_SHELL="${FEATURE_SHELL:-1}"
FEATURE_TERMUX_BOOT="${FEATURE_TERMUX_BOOT:-1}"

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

confirm() {
    local prompt="$1"
    local response
    echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

#===============================================================================
# Dependency Check & Installation
#===============================================================================

check_dependencies() {
    info "Checking dependencies..."
    
    local missing=()
    
    # Check for required commands
    for cmd in tmux zsh jq curl git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        warn "Missing dependencies: ${missing[*]}"
        
        if confirm "Install missing dependencies?"; then
            pkg update -y
            pkg install -y "${missing[@]}"
            success "Dependencies installed"
        else
            error "Cannot proceed without dependencies"
            return 1
        fi
    fi
    
    success "All dependencies satisfied"
}

#===============================================================================
# Backup & Restore
#===============================================================================

backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"
    
    info "Creating backup at: $backup_path"
    mkdir -p "$backup_path"
    
    # Backup existing configs
    [ -f "$HOME/.tmux.conf" ] && cp "$HOME/.tmux.conf" "$backup_path/"
    [ -d "$HOME/.tmux" ] && cp -r "$HOME/.tmux" "$backup_path/"
    [ -d "$HOME/.picoclaw" ] && cp -r "$HOME/.picoclaw" "$backup_path/"
    [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$backup_path/"
    [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$backup_path/"
    [ -f "$HOME/.profile" ] && cp "$HOME/.profile" "$backup_path/"
    [ -d "$HOME/.termux/boot" ] && cp -r "$HOME/.termux/boot" "$backup_path/"
    
    # Create backup info
    cat > "$backup_path/backup_info.txt" << EOF
Backup Date: $(date)
Version: $VERSION
Features Backed Up:
$(declare -p FEATURE_TMUX FEATURE_PICOCLAW FEATURE_SHELL FEATURE_TERMUX_BOOT 2>/dev/null || echo "N/A")
EOF
    
    # Create archive
    local archive="${BACKUP_DIR}/backup_${timestamp}.tar.gz"
    tar -czf "$archive" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
    rm -rf "$backup_path"
    
    success "Backup created: $archive"
    echo "$archive"
}

restore() {
    local archive="$1"
    
    if [ ! -f "$archive" ]; then
        error "Backup not found: $archive"
        return 1
    fi
    
    info "Restoring from: $archive"
    
    # Extract to temp
    local temp_dir=$(mktemp -d)
    tar -xzf "$archive" -C "$temp_dir"
    local backup_path=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [ -z "$backup_path" ]; then
        error "Invalid backup archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore configs
    [ -f "$backup_path/.tmux.conf" ] && cp "$backup_path/.tmux.conf" "$HOME/"
    [ -d "$backup_path/.tmux" ] && cp -r "$backup_path/.tmux" "$HOME/"
    [ -d "$backup_path/.picoclaw" ] && cp -r "$backup_path/.picoclaw" "$HOME/"
    [ -f "$backup_path/.zshrc" ] && cp "$backup_path/.zshrc" "$HOME/"
    [ -f "$backup_path/.zshenv" ] && cp "$backup_path/.zshenv" "$HOME/"
    [ -f "$backup_path/.profile" ] && cp "$backup_path/.profile" "$HOME/"
    [ -d "$backup_path/boot" ] && cp -r "$backup_path/boot" "$HOME/.termux/"
    
    rm -rf "$temp_dir"
    
    success "Backup restored successfully"
}

list_backups() {
    info "Available backups:"
    ls -lh "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null || echo "No backups found"
}

#===============================================================================
# Feature Installation
#===============================================================================

install_tmux() {
    info "Installing TMUX configuration..."
    
    # Install tmux plugins
    mkdir -p "$HOME/.tmux/plugins"
    
    # TPM
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    fi
    
    # Resurrect
    if [ ! -d "$HOME/.tmux/plugins/tmux-resurrect" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tmux-resurrect "$HOME/.tmux/plugins/tmux-resurrect"
    fi
    
    # Continuum
    if [ ! -d "$HOME/.tmux/plugins/tmux-continuum" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tmux-continuum "$HOME/.tmux/plugins/tmux-continuum"
    fi
    
    # Install tmux.conf
    cp "${CONFIG_DIR}/tmux/tmux.conf" "$HOME/.tmux.conf"
    
    # Install session launcher
    mkdir -p "$HOME/.tmux"
    cp "${CONFIG_DIR}/tmux/session-launcher.sh" "$HOME/.tmux/session-launcher.sh"
    chmod +x "$HOME/.tmux/session-launcher.sh"
    
    success "TMUX installed"
}

install_picoclaw() {
    info "Installing Picoclaw configuration..."
    
    mkdir -p "$HOME/.picoclaw/scripts"
    mkdir -p "$HOME/.picoclaw/logs"
    mkdir -p "$HOME/.picoclaw/workspace"
    
    # Copy config template
    cp "${CONFIG_DIR}/picoclaw/config.json.template" "$HOME/.picoclaw/config.json"
    
    # Copy scripts
    for script in "${CONFIG_DIR}"/picoclaw/scripts/*.sh; do
        [ -f "$script" ] || continue
        cp "$script" "$HOME/.picoclaw/scripts/"
        chmod +x "$HOME/.picoclaw/scripts/$(basename "$script")"
    done
    
    success "Picoclaw installed"
}

install_shell() {
    info "Installing shell configuration..."
    
    # Install zshenv (with user customization prompt)
    if [ ! -f "$HOME/.zshenv" ]; then
        cp "${CONFIG_DIR}/shell/zshenv.template" "$HOME/.zshenv"
    else
        warn " ~/.zshenv exists - skipping (backup first to replace)"
    fi
    
    # Install zshrc aliases (append, don't replace)
    if grep -q "TMUX Session Launcher" "$HOME/.zshrc" 2>/dev/null; then
        info "Shell aliases already present in .zshrc"
    else
        cat >> "$HOME/.zshrc" << 'EOF'

# ═══════════════════════════════════════════════════════════════════════
# TMUX Session Launcher (setup-install)
# ═══════════════════════════════════════════════════════════════════════
LAUNCHER="$HOME/.tmux/session-launcher.sh"
alias tmux-launch='$LAUNCHER'
alias tmux-all='$LAUNCHER all'
alias tmux-status='$LAUNCHER status'

# Quick session shortcuts
alias t-main='tmux attach -t main 2>/dev/null || ($LAUNCHER main && tmux attach -t main)'
alias t-mac='tmux attach -t mac 2>/dev/null || ($LAUNCHER mac && tmux attach -t mac)'
alias t-pc='tmux attach -t pc 2>/dev/null || ($LAUNCHER pc && tmux attach -t pc)'
alias t-debian='tmux attach -t debian 2>/dev/null || ($LAUNCHER dev && tmux attach -t dev)'
alias t-dev='tmux attach -t dev 2>/dev/null || ($LAUNCHER dev && tmux attach -t dev)'
alias t-picoclaw='tmux attach -t picoclaw 2>/dev/null || ($LAUNCHER picoclaw && tmux attach -t picoclaw)'
alias t-opencode='tmux attach -t opencode 2>/dev/null || ($LAUNCHER opencode && tmux attach -t opencode)'
alias t-codex='tmux attach -t codespace 2>/dev/null || ($LAUNCHER codex && tmux attach -t codespace)'
EOF
    fi
    
    success "Shell configuration installed"
}

install_termux_boot() {
    info "Installing Termux:Boot scripts..."
    
    mkdir -p "$HOME/.termux/boot"
    
    # Install boot scripts
    for script in "${REPO_DIR}/scripts/termux/"*.sh; do
        [ -f "$script" ] || continue
        cp "$script" "$HOME/.termux/boot/"
        chmod +x "$HOME/.termux/boot/$(basename "$script")"
    done
    
    success "Termux:Boot scripts installed"
}

#===============================================================================
# Upgrade
#===============================================================================

upgrade() {
    info "Upgrading setup..."
    
    # Pull latest from repo
    if [ -d "${REPO_DIR}/.git" ]; then
        cd "$REPO_DIR"
        git fetch origin
        git pull origin main
    fi
    
    # Reinstall selected features
    [ "$FEATURE_TMUX" = "1" ] && install_tmux
    [ "$FEATURE_PICOCLAW" = "1" ] && install_picoclaw
    [ "$FEATURE_SHELL" = "1" ] && install_shell
    [ "$FEATURE_TERMUX_BOOT" = "1" ] && install_termux_boot
    
    success "Upgrade complete"
}

#===============================================================================
# Validation Tests
#===============================================================================

run_tests() {
    info "Running validation tests..."
    
    local failed=0
    local passed=0
    
    # Test 1: Check tmux config
    echo -n "Testing tmux config... "
    if tmux source-file "$HOME/.tmux.conf" 2>/dev/null; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    # Test 2: Check picoclaw config
    echo -n "Testing picoclaw config... "
    if jq empty "$HOME/.picoclaw/config.json" 2>/dev/null; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    # Test 3: Check shell config
    echo -n "Testing shell config... "
    if [ -f "$HOME/.zshenv" ]; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    # Test 4: Check tmux plugins
    echo -n "Testing tmux plugins... "
    if [ -d "$HOME/.tmux/plugins/tpm" ]; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    # Test 5: Check session launcher
    echo -n "Testing session launcher... "
    if [ -x "$HOME/.tmux/session-launcher.sh" ]; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    # Test 6: Check picoclaw scripts
    echo -n "Testing picoclaw scripts... "
    if [ -x "$HOME/.picoclaw/scripts/picoclaw-autostart.sh" ]; then
        success "OK"
        ((passed++))
    else
        error "FAILED"
        ((failed++))
    fi
    
    echo ""
    info "Results: $passed passed, $failed failed"
    
    [ $failed -eq 0 ]
}

#===============================================================================
# Interactive TUI
#===============================================================================

show_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     Termux-Proot Development Environment Setup v${VERSION}       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Please select features to install:"
    echo ""
    
    echo -e "  ${GREEN}1${NC}) TMUX with plugins (resurrect, continuum)"
    echo -e "  ${GREEN}2${NC}) Picoclaw (AI assistant with Ollama)"
    echo -e "  ${GREEN}3${NC}) Shell configuration (zsh aliases)"
    echo -e "  ${GREEN}4${NC}) Termux:Boot scripts"
    echo -e "  ${GREEN}5${NC}) All of the above"
    echo -e "  ${GREEN}6${NC}) Custom selection"
    echo ""
    echo "  ─────────────────────────────────────"
    echo "  ${YELLOW}B${NC}) Backup current configuration"
    echo "  ${YELLOW}R${NC}) Restore from backup"
    echo "  ${YELLOW}U${NC}) Upgrade existing installation"
    echo "  ${YELLOW}T${NC}) Run validation tests"
    echo "  ${YELLOW}Q${NC}) Quit"
    echo ""
}

get_feature_selection() {
    local choice="$1"
    
    case "$choice" in
        1) FEATURE_TMUX=1; FEATURE_PICOCLAW=0; FEATURE_SHELL=0; FEATURE_TERMUX_BOOT=0 ;;
        2) FEATURE_TMUX=0; FEATURE_PICOCLAW=1; FEATURE_SHELL=0; FEATURE_TERMUX_BOOT=0 ;;
        3) FEATURE_TMUX=0; FEATURE_PICOCLAW=0; FEATURE_SHELL=1; FEATURE_TERMUX_BOOT=0 ;;
        4) FEATURE_TMUX=0; FEATURE_PICOCLAW=0; FEATURE_SHELL=0; FEATURE_TERMUX_BOOT=1 ;;
        5) FEATURE_TMUX=1; FEATURE_PICOCLAW=1; FEATURE_SHELL=1; FEATURE_TERMUX_BOOT=1 ;;
        6)
            echo ""
            echo "Select features (y/n for each):"
            echo -n "TMUX? [Y/n]: "; read -r yn; FEATURE_TMUX=$([[ "$yn" =~ ^[Nn]$ ]] && echo 0 || echo 1)
            echo -n "Picoclaw? [Y/n]: "; read -r yn; FEATURE_PICOCLAW=$([[ "$yn" =~ ^[Nn]$ ]] && echo 0 || echo 1)
            echo -n "Shell? [Y/n]: "; read -r yn; FEATURE_SHELL=$([[ "$yn" =~ ^[Nn]$ ]] && echo 0 || echo 1)
            echo -n "Termux:Boot? [Y/n]: "; read -r yn; FEATURE_TERMUX_BOOT=$([[ "$yn" =~ ^[Nn]$ ]] && echo 0 || echo 1)
            ;;
        *) return 1 ;;
    esac
}

interactive_setup() {
    while true; do
        show_menu
        echo -n "Select option: "
        read -r choice
        
        case "$choice" in
            1|2|3|4|5|6)
                get_feature_selection "$choice"
                break
                ;;
            B|b)
                backup
                continue
                ;;
            R|r)
                list_backups
                echo -n "Enter backup file: "
                read -r backup_file
                restore "$backup_file"
                continue
                ;;
            U|u)
                upgrade
                continue
                ;;
            T|t)
                run_tests
                echo -en "\nPress Enter to continue..."
                read
                continue
                ;;
            Q|q)
                echo "Goodbye!"
                exit 0
                ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

#===============================================================================
# Main
#===============================================================================

main() {
    mkdir -p "$BACKUP_DIR"
    log "Setup started: $VERSION"
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        interactive_setup
    else
        while [ $# -gt 0 ]; do
            case "$1" in
                --tmux) FEATURE_TMUX=1 ;;
                --picoclaw) FEATURE_PICOCLAW=1 ;;
                --shell) FEATURE_SHELL=1 ;;
                --termux-boot) FEATURE_TERMUX_BOOT=1 ;;
                --all) FEATURE_TMUX=1; FEATURE_PICOCLAW=1; FEATURE_SHELL=1; FEATURE_TERMUX_BOOT=1 ;;
                --backup) backup; exit 0 ;;
                --restore) restore "$2"; exit 0 ;;
                --upgrade) upgrade; exit 0 ;;
                --test) run_tests; exit 0 ;;
                --version) echo "v$VERSION"; exit 0 ;;
                --help|-h)
                    echo "Usage: $0 [OPTIONS]"
                    echo ""
                    echo "Options:"
                    echo "  --tmux         Install TMUX configuration"
                    echo "  --picoclaw     Install Picoclaw configuration"
                    echo "  --shell        Install shell configuration"
                    echo "  --termux-boot  Install Termux:Boot scripts"
                    echo "  --all          Install all features"
                    echo "  --backup       Create backup"
                    echo "  --restore FILE Restore from backup"
                    echo "  --upgrade      Upgrade existing installation"
                    echo "  --test         Run validation tests"
                    echo "  --version      Show version"
                    echo "  --help         Show this help"
                    exit 0
                    ;;
                *) error "Unknown option: $1" ;;
            esac
            shift
        done
    fi
    
    # Install selected features
    info "Installing features..."
    
    check_dependencies
    
    [ "$FEATURE_TMUX" = "1" ] && install_tmux
    [ "$FEATURE_PICOCLAW" = "1" ] && install_picoclaw
    [ "$FEATURE_SHELL" = "1" ] && install_shell
    [ "$FEATURE_TERMUX_BOOT" = "1" ] && install_termux_boot
    
    success "Installation complete!"
    
    if confirm "Run validation tests?"; then
        run_tests
    fi
    
    info "Done! Restart your shell or run: source ~/.zshrc"
}

main "$@"
