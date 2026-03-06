#!/usr/bin/env bash
#===============================================================================
# Picoclaw Ollama Supervisor
# Manages SSH tunnel to remote Ollama server with auto-reconnect
#===============================================================================

ACTION="${1:-status}"
HOST="${PICOCLAW_OLLAMA_HOST:-100.69.90.87}"
USER="${PICOCLAW_OLLAMA_USER:-nikhilsutra}"
LPORT="${PICOCLAW_OLLAMA_LOCAL_PORT:-11434}"
RPORT="${PICOCLAW_OLLAMA_REMOTE_PORT:-11434}"
PIDFILE="${HOME}/.picoclaw/ollama.pid"
PATTERN="ssh .*127.0.0.1:${LPORT}:127.0.0.1:${RPORT} .*${USER}@${HOST}"

is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

start() {
    if is_running; then
        echo "Already running (pid $(cat "$PIDFILE"))"
        return 0
    fi
    
    # Kill any existing tunnel
    pkill -f "$PATTERN" 2>/dev/null || true
    sleep 1
    
    ssh -N \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -L "127.0.0.1:${LPORT}:127.0.0.1:${RPORT}" \
        "${USER}@${HOST}" &
    
    echo $! > "$PIDFILE"
    sleep 2
    
    if is_running; then
        echo "Tunnel started: 127.0.0.1:${LPORT} -> ${HOST}:${RPORT}"
    else
        echo "Failed to start tunnel"
        return 1
    fi
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
    pkill -f "$PATTERN" 2>/dev/null || true
    echo "Tunnel stopped"
}

status() {
    if is_running; then
        echo "STATUS=running pid=$(cat "$PIDFILE")"
        pgrep -af "$PATTERN" || true
    else
        echo "STATUS=stopped"
    fi
}

case "$ACTION" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    restart) stop; start ;;
    *) echo "Usage: $0 {start|stop|status|restart}" ;;
esac
