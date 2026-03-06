#!/usr/bin/env bash
#===============================================================================
# Picoclaw Autostart Script
# Starts Picoclaw with Ollama tunnel on shell initialization
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${HOME}/.picoclaw/logs"
LOG_FILE="${LOG_DIR}/autostart.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

is_running() {
    [ -f "${HOME}/.picoclaw/pid" ] && kill -0 "$(cat "${HOME}/.picoclaw/pid")" 2>/dev/null
}

start_ollama_tunnel() {
    log "Starting Ollama tunnel..."
    
    # Check if already running
    if is_running; then
        log "Picoclaw already running (pid $(cat ${HOME}/.picoclaw/pid))"
        return 0
    fi
    
    # Start the supervisor
    "$SCRIPT_DIR/picoclaw-ollama-supervisor.sh" start >> "$LOG_FILE" 2>&1
    
    if is_running; then
        log "Picoclaw started successfully"
        return 0
    else
        log "Failed to start Picoclaw"
        return 1
    fi
}

case "${1:-start}" in
    start) start_ollama_tunnel ;;
    status)
        if is_running; then
            echo "Running (pid $(cat ${HOME}/.picoclaw/pid))"
        else
            echo "Not running"
        fi
        ;;
    stop)
        log "Stopping Picoclaw..."
        "$SCRIPT_DIR/picoclaw-ollama-supervisor.sh" stop >> "$LOG_FILE" 2>&1
        ;;
    restart)
        "$0" stop
        sleep 1
        "$0" start
        ;;
esac
