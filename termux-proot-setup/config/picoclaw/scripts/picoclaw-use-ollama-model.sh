#!/usr/bin/env bash
#===============================================================================
# Picoclaw Model Switcher
# Switch between different Ollama models
#===============================================================================

if [ $# -ne 1 ]; then
    echo "Usage: $0 <model-name>"
    echo "Example: $0 qwen3.5:9b-ctx64k"
    exit 1
fi

MODEL="$1"
HOST="${PICOCLAW_OLLAMA_HOST:-100.69.90.87}"
USER="${PICOCLAW_OLLAMA_USER:-nikhilsutra}"
CONFIG="${PICOCLAW_CONFIG:-${HOME}/.picoclaw/config.json}"

# Verify model exists on remote
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "${USER}@${HOST}" "ollama list | grep -Fx '${MODEL}'" >/dev/null 2>&1; then
    echo "Model '${MODEL}' not found on remote"
    echo "Available models:"
    ssh "${USER}@${HOST}" "ollama list"
    exit 2
fi

# Update config
jq --arg model "ollama/${MODEL}" \
   '.agents.defaults.model = $model' \
   "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

echo "Switched to model: ${MODEL}"
