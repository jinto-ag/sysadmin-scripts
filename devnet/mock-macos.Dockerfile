FROM ubuntu:24.04

# Remove interactive prompts during apt
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies needed by devnet.sh
RUN apt-get update && apt-get install -y \
    curl wget jq git sudo gawk lsof dnsutils \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────────────────────
# CORE macOS COMMAND MOCKS
# ──────────────────────────────────────────────────────────────
# uname: Fake Darwin and arm64 architecture
RUN echo '#!/bin/bash\nif [ "$1" == "-m" ]; then echo "arm64"; else echo "Darwin"; fi' > /usr/local/bin/uname \
    && chmod +x /usr/local/bin/uname

# sw_vers: Fake OS version
RUN echo '#!/bin/bash\necho "14.5"' > /usr/local/bin/sw_vers \
    && chmod +x /usr/local/bin/sw_vers

# stat: Fake macOS stat structure for permissions parsing
RUN mv /usr/bin/stat /usr/bin/stat.real && \
    echo '#!/bin/bash\nif [[ "$1" == "-f" ]]; then echo "drwx------"; else /usr/bin/stat.real "$@"; fi' > /usr/local/bin/stat && chmod +x /usr/local/bin/stat

# sysctl: Fake Apple Silicon Memory (32GB = 34359738368 bytes) & iogpu
RUN echo '#!/bin/bash\nif [[ "$*" == *"hw.memsize"* ]]; then echo 34359738368; else echo 0; fi' > /usr/local/bin/sysctl \
    && chmod +x /usr/local/bin/sysctl

# df: Fake 'df -g' which is macOS specific
RUN mv /bin/df /bin/df.real && \
    echo '#!/bin/bash\nif [ "$1" == "-g" ]; then echo "Filesystem 1G-blocks Used Available Capacity iused ifree %iused Mounted on"; echo "/dev/disk3s1 465 142 323 31% 292813 3317714 8% /"; else /bin/df.real "$@"; fi' > /usr/local/bin/df \
    && chmod +x /usr/local/bin/df

# launchctl / sandbox-exec
RUN echo '#!/bin/bash\nexit 0' > /usr/local/bin/launchctl && chmod +x /usr/local/bin/launchctl
RUN echo '#!/bin/bash\nshift 2; "$@"' > /usr/bin/sandbox-exec && chmod +x /usr/bin/sandbox-exec
RUN echo '#!/bin/bash\nhostname mac-mock' > /usr/local/bin/scutil && chmod +x /usr/local/bin/scutil
RUN echo '#!/bin/bash\nexit 0' > /usr/local/bin/defaults && chmod +x /usr/local/bin/defaults
RUN echo '#!/bin/bash\nexit 0' > /usr/local/bin/networksetup && chmod +x /usr/local/bin/networksetup

# macOS Application Firewall Mock
RUN mkdir -p /usr/libexec/ApplicationFirewall && \
    echo '#!/bin/bash\nexit 0' > /usr/libexec/ApplicationFirewall/socketfilterfw && \
    chmod +x /usr/libexec/ApplicationFirewall/socketfilterfw

# ──────────────────────────────────────────────────────────────
# THIRD PARTY TOOLING MOCKS (Homebrew, Tailscale, Ollama)
# ──────────────────────────────────────────────────────────────
RUN mkdir -p /opt/homebrew/bin
RUN echo '#!/bin/bash\necho "Brew Mock"' > /opt/homebrew/bin/brew && chmod +x /opt/homebrew/bin/brew
RUN rm -f /usr/bin/pgrep && echo '#!/bin/bash\nexit 0' > /usr/bin/pgrep && chmod +x /usr/bin/pgrep
RUN echo '#!/bin/bash\nif [[ "$*" == *"11434"* ]]; then exit 0; else /usr/bin/curl "$@"; fi' > /usr/local/bin/curl && chmod +x /usr/local/bin/curl
RUN echo '#!/bin/bash\nif [[ "$*" == *"ip -4"* ]]; then echo "100.101.102.103"; exit 0; fi\nexit 0' > /opt/homebrew/bin/tailscale && chmod +x /opt/homebrew/bin/tailscale
RUN echo '#!/bin/bash\nexit 0' > /opt/homebrew/bin/tailscaled && chmod +x /opt/homebrew/bin/tailscaled
RUN echo '#!/bin/bash\nexit 0' > /opt/homebrew/bin/ollama && chmod +x /opt/homebrew/bin/ollama
RUN echo '#!/bin/bash\nif [[ "$*" == *"machine list"* ]]; then echo "devbox true"; else exit 0; fi' > /opt/homebrew/bin/podman && chmod +x /opt/homebrew/bin/podman
RUN echo '#!/bin/bash\necho "v20.0.0"' > /opt/homebrew/bin/node && chmod +x /opt/homebrew/bin/node
RUN echo '#!/bin/bash\nexit 0' > /opt/homebrew/bin/npm && chmod +x /opt/homebrew/bin/npm
RUN echo '#!/bin/bash\nexit 0' > /opt/homebrew/bin/opencode && chmod +x /opt/homebrew/bin/opencode

# Mock 'gum' manually so tests pass smoothly without needing binary installation
RUN echo '#!/bin/bash\nif [[ "$1" == "style" ]]; then shift; echo "$@"; elif [[ "$1" == "confirm" ]]; then exit 0; else exit 0; fi' > /opt/homebrew/bin/gum && chmod +x /opt/homebrew/bin/gum

RUN cp -R /opt/homebrew/bin/* /usr/local/bin/ && ln -s /usr/local/bin/tailscale /usr/bin/tailscale && ln -s /usr/local/bin/tailscaled /usr/bin/tailscaled

ENV PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# Setup a non-root user matching the linux user to avoid permission clashes on mounted scripts
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create MacOS mock LaunchDaemon directories
RUN mkdir -p /Library/LaunchDaemons /Library/LaunchAgents && \
    chown -R root:root /Library/LaunchDaemons /Library/LaunchAgents
RUN su - devuser -c "mkdir -p ~/Library/LaunchAgents"

WORKDIR /scripts
USER devuser

CMD ["bash"]
