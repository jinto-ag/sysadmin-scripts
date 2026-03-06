#!/data/data/com.termux/files/usr/bin/bash
#===============================================================================
# Termux:Boot - Start tmux server for session persistence
# Run at Android boot via Termux:Boot app
#===============================================================================

termux-wake-lock

# Ensure tmux server is running
if ! tmux has-session 2>/dev/null; then
    tmux new-session -d -s main
fi
