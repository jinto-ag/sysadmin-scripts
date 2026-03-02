#!/bin/bash
podman build -t mock-macos -f mock-macos.Dockerfile .

# Extract key safely
TS_KEY=$(grep -E '^TAILSCALE_AUTHKEY=' .env | cut -d= -f2-)
TS_KEY="${TS_KEY%\"}"
TS_KEY="${TS_KEY#\"}"
TS_KEY="${TS_KEY%\'}"
TS_KEY="${TS_KEY#\'}"

podman run --rm -e TAILSCALE_AUTHKEY="$TS_KEY" -v "$(pwd):/host" -it mock-macos bash -c "cp /host/devnet.sh /tmp/devnet.sh && chmod +x /tmp/devnet.sh && cd /tmp && ./devnet.sh install && ./devnet.sh doctor && ./devnet.sh status && ./devnet.sh stop && ./devnet.sh start"
