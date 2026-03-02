# DevNet Setup Script

An enterprise-grade, production-ready macOS & Podman development environment bootstrap script.

## Features

- **Tailscale**: Secure headless mesh network connectivity and SSH.
- **Ollama**: Local AI model execution, sandboxed and optimized for Apple Silicon Metal GPUs.
- **Podman**: Developer sandbox virtualization for seamless containerized workflows.
- **Security**: Built-in macOS application firewall configuration, sandboxing (`sandbox-exec`), and strict directory permissions (`drwx------`).

## Usage

### One-line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main/devnet/devnet.sh | bash -s -- install
```

### Local Execution

If you cloned the repository locally:

```bash
./devnet.sh install
```

### Dashboard & Status

To view a live status dashboard of all running background daemons:

```bash
./devnet.sh status
```

### Diagnostics

Run a complete health check that sweeps all processes and background configurations:

```bash
./devnet.sh doctor
```

### Process Management

You can smoothly stop or start the automated background jobs:

```bash
./devnet.sh stop
./devnet.sh start
```

## Testing (Mock MacOS)

A secure Podman container mock-engine is provided to evaluate Apple's native hooks (like `launchctl` and `sandbox-exec`) on a standard Linux CI/CD host avoiding dry-run inconsistencies:

```bash
# Requires an active tailscale auth key
echo "TAILSCALE_AUTHKEY=tskey-auth-xxxx" > .env
./test-mock.sh
```
