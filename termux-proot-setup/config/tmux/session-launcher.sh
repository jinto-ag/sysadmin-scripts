#!/usr/bin/env bash
#===============================================================================
# TMUX Session Launcher with Retry & Logging
# Handles auto-starting apps in tmux sessions with detailed logging
#===============================================================================

set -euo pipefail

# Configuration
LOG_DIR="${HOME}/.tmux/session-logs"
SESSION_LOG="$LOG_DIR/launcher.log"
MAX_RETRIES=3
RETRY_DELAY=5

# Colors
RED='\033m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SESSION_LOG"
}

log_success() { log "${GREEN}✓${NC} $*"; }
log_error() { log "${RED}✗${NC} $*"; }
log_warn() { log "${YELLOW}⚠${NC} $*"; }
log_info() { log "  $*"; }

mkdir -p "$LOG_DIR"

session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

kill_session() {
    local session="$1"
    if session_exists "$session"; then
        log_info "Killing: $session"
        tmux kill-session -t "$session" 2>/dev/null || true
        sleep 1
    fi
}

send_to_session() {
    local session="$1"
    local cmd="$2"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if tmux send-keys -t "$session" "$cmd" C-m 2>/dev/null; then
            log_info "Sent: $cmd"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Retry $retry/$MAX_RETRIES"
        sleep $RETRY_DELAY
    done
    log_error "Failed after $MAX_RETRIES"
    return 1
}

launch_session() {
    local session="$1"
    local app="$2"
    local args="${3:-}"
    
    log "=========================================="
    log "Launching: $session -> $app $args"
    
    kill_session "$session"
    
    # Create session
    log_info "Creating session: $session"
    if ! tmux new-session -d -s "$session" "zsh" 2>&1 | tee -a "$SESSION_LOG"; then
        log_error "Failed: $session"
        return 1
    fi
    
    sleep 1
    
    # Handle different app types
    case "$app" in
        ssh)
            log_info "SSH session: $args"
            send_to_session "$session" "$args"
            ;;
        proot)
            log_info "Logging into proot Debian..."
            send_to_session "$session" "proot-distro login debian --user root --shared-tmp --termux-home"
            sleep 3
            
            if [[ "$session" == "picoclaw" ]]; then
                log_info "Starting Ollama tunnel..."
                send_to_session "$session" "$HOME/.picoclaw/scripts/picoclaw-autostart.sh start"
                send_to_session "$session" "sleep infinity"
            fi
            ;;
        opencode|codex)
            log_info "Starting: $app"
            send_to_session "$session" "$app"
            sleep 2
            ;;
        gh)
            log_info "GitHub Codespace: $args"
            send_to_session "$session" "$args"
            ;;
        zsh)
            log_info "Shell ready"
            ;;
    esac
    
    log_success "Session $session created"
}

# Main
case "${1:-all}" in
    opencode)   launch_session "opencode" "opencode" ;;
    picoclaw)   launch_session "picoclaw" "proot" ;;
    codex)      launch_session "codespace" "gh" "gh cs ssh -c glorious-space-fiesta-766j5pwrwgr2r66r" ;;
    debian|dev) launch_session "dev" "proot" ;;
    mac)        launch_session "mac" "ssh" "nikhilsutra@100.69.90.87" ;;
    pc)         launch_session "pc" "ssh" "jinto-ag@100.92.190.58" ;;
    main)       launch_session "main" "zsh" ;;
    all)
        log "Launching all sessions..."
        launch_session "main" "zsh"
        launch_session "mac" "ssh" "nikhilsutra@100.69.90.87"
        launch_session "pc" "ssh" "jinto-ag@100.92.190.58"
        launch_session "dev" "proot"
        launch_session "opencode" "opencode"
        launch_session "picoclaw" "proot"
        launch_session "codespace" "gh" "gh cs ssh -c glorious-space-fiesta-766j5pwrwgr2r66r"
        
        log "=========================================="
        log "All sessions launched!"
        tmux ls
        ;;
    status)
        echo "Sessions:"
        tmux ls 2>/dev/null || echo "None"
        ;;
    *)
        echo "Usage: $0 {opencode|picoclaw|codex|debian|mac|pc|main|all|status}"
        ;;
esac
