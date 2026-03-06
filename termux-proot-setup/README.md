# Termux + PRoot Debian Development Environment

Enterprise-grade setup for Termux with proot-distro (Debian) for local development with remote Ollama models via SSH tunnel.

## Features

- **Remote Ollama Integration**: Connect to Mac's Ollama via SSH tunnel using picoclaw
- **Tmux Session Management**: Persistent tmux sessions with tmux-continuum and tmux-resurrect
- **Shell Configuration**: Pre-configured zsh environment with useful aliases
- **Termux Boot Scripts**: Auto-start tmux sessions on device boot
- **Backup/Restore**: Full system backup and restore capabilities
- **Interactive Setup**: TUI-based installation with feature selection

## Quick Start

```bash
# Clone and run setup
git clone https://github.com/YOUR_USERNAME/termux-proot-setup.git
cd termux-proot-setup
chmod +x setup.sh
./setup.sh --all
```

## Interactive Mode

```bash
./setup.sh
```

## Feature Flags

- `--tmux` - Install tmux configuration with plugins
- `--picoclaw` - Install picoclaw with SSH tunnel setup
- `--shell` - Install shell configuration (zshenv, aliases)
- `--termux-boot` - Install Termux boot scripts
- `--all` - Install all features

## Backup & Restore

```bash
# Create backup
./setup.sh --backup

# Restore from backup
./setup.sh --restore backup-2024-01-01.tar.gz

# Upgrade from repo
./setup.sh --upgrade
```

## Validation

```bash
# Run validation tests
./setup.sh --test
```

## Configuration

Edit templates in `config/` directory:
- `config/picoclaw/config.json.template` - Ollama connection settings
- `config/tmux/tmux.conf` - Tmux configuration
- `config/shell/zshenv.template` - Shell environment

## Security

**IMPORTANT**: Never commit secrets to this repository.
- SSH keys should be managed separately
- API tokens should use environment variables
- See `.gitignore` for excluded files

## Requirements

- Termux (Android)
- proot-distro (Debian)
- SSH access to remote Ollama server (optional)

## License

MIT
