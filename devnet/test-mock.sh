#!/bin/bash
podman build -t mock-macos -f mock-macos.Dockerfile .

# Extract key safely
TS_KEY=$(grep -E '^TAILSCALE_AUTHKEY=' .env | cut -d= -f2-)
TS_KEY="${TS_KEY%\"}"
TS_KEY="${TS_KEY#\"}"
TS_KEY="${TS_KEY%\'}"
TS_KEY="${TS_KEY#\'}"

podman run --rm -e TAILSCALE_AUTHKEY="$TS_KEY" -v "$(pwd):/host" -it mock-macos bash -c "cp /host/setup.sh /tmp/setup.sh && chmod +x /tmp/setup.sh && cd /tmp && ./setup.sh --force --defaults install && ./setup.sh --force doctor && ./setup.sh status && ./setup.sh stop && ./setup.sh start"
