#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# tmux-sessions.sh — Manual session launcher
# ═══════════════════════════════════════════════════════════════════════
# NOTE: This script is for MANUAL session creation.
# For automatic session persistence after reboot, tmux-continuum handles 
# restoration automatically when you attach to tmux.
# 
# To disable auto-start at boot: rm ~/.termux/boot/tmux-sessions.sh
# ═══════════════════════════════════════════════════════════════════════

# Exit if not in interactive mode (prevent auto-run at boot)
if [ ! -t 0 ]; then
    exit 0
fi

# Function to start a session in proot debian
start_proot_session() {
    local session_name="$1"
    local session_command="$2"
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "Session '$session_name' already exists - attaching"
        tmux attach-session -t "$session_name"
        return $?
    fi
    
    if [ -n "$session_command" ]; then
        tmux new-session -d -s "$session_name" "$session_command"
    else
        tmux new-session -d -s "$session_name"
    fi
    echo "Created session: $session_name"
    tmux attach-session -t "$session_name"
}

# Main menu
case "${1:-menu}" in
    mac)
        start_proot_session "mac" "ssh nikhilsutra@100.69.90.87"
        ;;
    pc)
        start_proot_session "pc" "ssh jinto-ag@100.92.190.58"
        ;;
    opencode)
        start_proot_session "opencode" "proot-distro login debian --user root --shared-tmp --termux-home -c 'opencode || exec zsh'"
        ;;
    codex)
        start_proot_session "codex" "proot-distro login debian --user root --shared-tmp --termux-home -c 'codex || exec zsh'"
        ;;
    picoclaw)
        start_proot_session "picoclaw" "proot-distro login debian --user root --shared-tmp --termux-home -c 'source ~/.zshenv 2>/dev/null; ~/.picoclaw/scripts/picoclaw-autostart.sh start; sleep infinity'"
        ;;
    debian|dev)
        start_proot_session "debian" "proot-distro login debian --user root --shared-tmp --termux-home"
        ;;
    list)
        tmux list-sessions 2>/dev/null || echo "No sessions"
        ;;
    menu|*)
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║           TMUX SESSION LAUNCHER (Manual)                   ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║  Usage: tmux-sessions.sh <session>                         ║"
        echo "║                                                              ║"
        echo "║  Sessions:                                                  ║"
        echo "║    mac       → SSH to Mac (nikhilsutra@100.69.90.87)       ║"
        echo "║    pc        → SSH to PC (jinto-ag@100.92.190.58)          ║"
        echo "║    opencode  → OpenCode in proot Debian                    ║"
        echo "║    codex     → Codex in proot Debian                       ║"
        echo "║    picoclaw  → Picoclaw + Ollama tunnel                   ║"
        echo "║    debian    → proot Debian shell                         ║"
        echo "║    list      → List existing sessions                     ║"
        echo "║                                                              ║"
        echo "║  NOTE: For auto-restore after reboot, use tmux-continuum.  ║"
        echo "║        Attach to tmux to restore saved sessions.           ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        ;;
esac
