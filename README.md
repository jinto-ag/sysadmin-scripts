# SysAdmin Scripts

A collection of enterprise-grade system administration scripts for bootstrapping, securing, and maintaining development environments.

## Available Scripts

### [DevNet](devnet/README.md)

The `devnet` module provides an automated, enterprise-ready environment setup.
To install the `devnet` development environment directly from GitHub without cloning, run:

```bash
curl -fsSL https://raw.githubusercontent.com/jinto-ag/sysadmin-scripts/main/devnet/setup.sh | bash -s -- install
```

> **Note:** Be sure to review scripts before piping them into bash!

See the [DevNet Documentation](devnet/README.md) for full instructions, options, and architecture details.

### [Termux + PRoot Setup](termux-proot-setup/README.md)

Enterprise-grade setup for Termux with proot-distro (Debian) for local development with remote Ollama models via SSH tunnel.

Features:
- Remote Ollama Integration via SSH tunnel using picoclaw
- Tmux Session Management with tmux-continuum and tmux-resurrect
- Shell Configuration (zsh)
- Termux Boot Scripts for auto-start
- Backup & Restore capabilities
- Interactive TUI setup

```bash
cd termux-proot-setup
chmod +x setup.sh
./setup.sh --all
```

See the [Termux Setup Documentation](termux-proot-setup/README.md) for full instructions.
