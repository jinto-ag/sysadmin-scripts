#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot - Start tmux server for session persistence
# tmux-continuum will handle session restoration automatically

termux-wake-lock

# Ensure tmux server is running (continuum will restore sessions)
if ! tmux has-session 2>/dev/null; then
    # Start a detached session that will be restored by continuum
    tmux new-session -d -s main
fi
# Termux:Boot - Start tmux with continuum for session persistence

termux-wake-lock

# Start tmux server if not running
if ! tmux has-session 2>/dev/null; then
    tmux start-server
fi
