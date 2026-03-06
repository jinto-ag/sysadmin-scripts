#!/usr/bin/env bash
#===============================================================================
# TMUX Session Launcher with Retry & Logging
# Handles auto-starting apps in tmux sessions with detailed logging
#===============================================================================

set -euo pipefail

# Configuration
LOG_DIR="$HOME/.tmux/session-logs"
SESSION_LOG="$LOG_DIR/launcher.log"
MAX_RETRIES=3
RETRY_DELAY=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "$msg" | tee -a "$SESSION_LOG"
}

log_success() {
    log "${GREEN}✓${NC} $*"
}

log_error() {
    log "${RED}✗${NC} $*"
}

log_warn() {
    log "${YELLOW}⚠${NC} $*"
}

log_info() {
    log "  $*"
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Check if session exists
session_exists() {
    local session="$1"
    tmux has-session -t "$session" 2>/dev/null
}

# Kill existing session
kill_session() {
    local session="$1"
    if session_exists "$session"; then
        log_info "Killing existing session: $session"
        tmux kill-session -t "$session" 2>/dev/null || true
        sleep 1
    fi
}

# Send command to session with retry
send_to_session() {
    local session="$1"
    local cmd="$2"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if tmux send-keys -t "$session" "$cmd" C-m 2>/dev/null; then
            log_info "Sent to $session: $cmd"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Retry $retry/$MAX_RETRIES for sending to $session"
        sleep $RETRY_DELAY
    done
    
    log_error "Failed to send to $session after $MAX_RETRIES attempts"
    return 1
}

# Wait for session to be ready
wait_for_session() {
    local session="$1"
    local max_wait=10
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if session_exists "$session"; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    log_error "Session $session not ready after ${max_wait}s"
    return 1
}

# Launch session with app
launch_session() {
    local session="$1"
    local app="$2"
    local args="${3:-}"
    
    log "=========================================="
    log "Launching session: $session -> $app $args"
    log "=========================================="
    
    # Kill existing session
    kill_session "$session"
    
    # Create new session with zsh
    log_info "Creating session: $session"
    if ! tmux new-session -d -s "$session" "zsh" 2>&1 | tee -a "$SESSION_LOG"; then
        log_error "Failed to create session: $session"
        return 1
    fi
    
    # Wait for session to be ready
    if ! wait_for_session "$session"; then
        log_error "Session $session not ready"
        return 1
    fi
    
    # For SSH sessions, just wait
    if [[ "$app" == "ssh" ]]; then
        log_success "Session $session created (SSH - attach to use)"
        return 0
    fi
    
    # For proot-based apps, need to login first
    if [[ "$app" == "debian" ]] || [[ "$app" == "proot" ]]; then
        log_info "Logging into proot Debian..."
        
        # Send proot command
        send_to_session "$session" "proot-distro login debian --user root --shared-tmp --termux-home"
        
        # Wait for proot to initialize
        sleep 3
        
        # For picoclaw, start the tunnel
        if [[ "$session" == "picoclaw" ]]; then
            log_info "Starting picoclaw Ollama tunnel..."
            send_to_session "$session" "source ~/.zshenv 2>/dev/null || true"
            send_to_session "$session" "$HOME/.picoclaw/scripts/picoclaw-autostart.sh start"
            send_to_session "$session" "sleep infinity"
        fi
        
        log_success "Session $session created (proot Debian)"
        return 0
    fi
    
    # For local apps (opencode, codex, etc.)
    log_info "Starting app: $app"
    send_to_session "$session" "$app $args"
    
    # Wait a bit for app to start
    sleep 2
    
    log_success "Session $session created with $app"
    return 0
}

# Main
case "${1:-all}" in
    opencode)
        launch_session "opencode" "opencode"
        ;;
    picoclaw)
        launch_session "picoclaw" "proot"
        ;;
    codex|codespace)
        launch_session "codespace" "gh cs ssh -c glorious-space-fiesta-766j5pwrwgr2r66r"
        ;;
    debian|dev)
        launch_session "dev" "proot"
        ;;
    mac)
        launch_session "mac" "ssh" "nikhilsutra@100.69.90.87"
        ;;
    pc)
        launch_session "pc" "ssh" "jinto-ag@100.92.190.58"
        ;;
    main)
        launch_session "main" "zsh"
        ;;
    all)
        log "Launching all sessions..."
        launch_session "main" "zsh"
        launch_session "mac" "ssh" "nikhilsutra@100.69.90.87"
        launch_session "pc" "ssh" "jinto-ag@100.92.190.58"
        launch_session "dev" "proot"
        launch_session "opencode" "opencode"
        launch_session "picoclaw" "proot"
        launch_session "codespace" "gh cs ssh -c glorious-space-fiesta-766j5pwrwgr2r66r"
        
        log "=========================================="
        log "All sessions launched!"
        log "=========================================="
        tmux ls
        ;;
    status)
        log "Current sessions:"
        tmux ls 2>/dev/null || echo "No sessions"
        ;;
    *)
        echo "Usage: $0 {opencode|picoclaw|codex|debian|mac|pc|main|all|status}"
        echo ""
        echo "Sessions:"
        echo "  opencode   - OpenCode AI assistant"
        echo "  picoclaw   - Picoclaw with Ollama tunnel"
        echo "  codex      - GitHub Codespace"
        echo "  debian/dev - Proot Debian"
        echo "  mac        - SSH to Mac"
        echo "  pc         - SSH to PC"
        echo "  main       - Main shell"
        echo "  all        - Launch all sessions"
        echo "  status     - Show current status"
        ;;
esac
