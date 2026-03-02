#!/usr/bin/env bash

# ================================================================
#  setup.sh — Enterprise macOS AI Stack Manager v1.0.0
#
#  Stack:
#    • Ollama      → host (full Metal GPU), sandboxed via macOS
#                    sandbox-exec, bound to 127.0.0.1 only
#    • Tailscale   → headless system daemon, --accept-dns=false
#                    (guaranteed safe internet after setup)
#    • Podman      → isolated dev sandbox, zero access to model files
#    • gum         → interactive TUI configuration
#
#  Usage:
#    ./setup.sh install [--defaults]   Interactive or fully automated
#    ./setup.sh uninstall [--purge]    Remove everything (--purge = logs too)
#    ./setup.sh reset [--defaults]     Clean reinstall
#    ./setup.sh start                  Start all stopped services
#    ./setup.sh stop                   Stop services gracefully
#    ./setup.sh status                 Live health dashboard
#    ./setup.sh logs [svc]             Tail logs (ollama|tailscale|podman|all)
#    ./setup.sh doctor                 Diagnose + auto-repair
#    ./setup.sh version                Print version
#
#  Env override (any variable below can be pre-set to skip its prompt):
#    export TAILSCALE_AUTHKEY=tskey-auth-XXXX
#    export TAILSCALE_HOSTNAME=mac-ai
#    ./setup.sh install --defaults
# ================================================================

set -uo pipefail   # -u: unbound vars = error, -o pipefail: pipe failures caught
                   # NO global -e: every step has explicit error handling

umask 077

readonly DEVNET_VERSION="1.0.0"
readonly DEVNET_NAME="devnet"
DRY_RUN="false"
FORCE_MODE="false"

# ──────────────────────────────────────────────────────────────
# SYSTEM CONSTANTS
# ──────────────────────────────────────────────────────────────
CURRENT_USER="$(whoami)"
export CURRENT_USER
BREW_PREFIX="$([[ -d /opt/homebrew ]] && echo /opt/homebrew || echo /usr/local)"
readonly BREW_PREFIX
BREW_BIN="${BREW_PREFIX}/bin/brew"
readonly BREW_BIN
ARCH="$(uname -m)"
readonly ARCH
IS_APPLE_SILICON="$([[ "$ARCH" == "arm64" ]] && echo true || echo false)"
readonly IS_APPLE_SILICON
MACOS_VER="$(sw_vers -productVersion)"
readonly MACOS_VER
MACOS_MAJOR="$(echo "$MACOS_VER" | cut -d. -f1)"
readonly MACOS_MAJOR

# Paths (all scoped to current user — no global FS pollution)
readonly CONFIG_DIR="${HOME}/.config/${DEVNET_NAME}"
readonly DATA_DIR="${HOME}/.local/share/${DEVNET_NAME}"
readonly LOG_DIR="${HOME}/Library/Logs/${DEVNET_NAME}"
readonly MANIFEST="${CONFIG_DIR}/manifest"
readonly CONFIG_SNAPSHOT="${CONFIG_DIR}/config.env"
readonly SANDBOX_PROFILE="${DATA_DIR}/ollama.sb"
readonly WRAPPER_DIR="${DATA_DIR}/wrappers"

# LaunchAgent / LaunchDaemon identifiers
readonly PLIST_TS_DAEMON="/Library/LaunchDaemons/com.${DEVNET_NAME}.tailscaled.plist"
readonly PLIST_GPU_DAEMON="/Library/LaunchDaemons/com.${DEVNET_NAME}.gpu-memory.plist"
readonly PLIST_OLLAMA="${HOME}/Library/LaunchAgents/com.${DEVNET_NAME}.ollama.plist"
readonly PLIST_PODMAN="${HOME}/Library/LaunchAgents/com.${DEVNET_NAME}.podman-machine.plist"

# ──────────────────────────────────────────────────────────────
# USER DEFAULTS (overridden by interactive prompts or env vars)
# ──────────────────────────────────────────────────────────────
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-mac-ai}"
ENABLE_TAILSCALE_SSH="${ENABLE_TAILSCALE_SSH:-true}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_HOME="${OLLAMA_HOME:-${HOME}/.ollama}"
OLLAMA_ORIGINS="${OLLAMA_ORIGINS:-}"  # default set dynamically in phase_configure if empty
OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-4}"
OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-2}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-30m}"
GPU_MEMORY_PERCENT="${GPU_MEMORY_PERCENT:-80}"
ENABLE_SANDBOX="${ENABLE_SANDBOX:-true}"
PODMAN_MACHINE_NAME="${PODMAN_MACHINE_NAME:-devbox}"
PODMAN_CPUS="${PODMAN_CPUS:-4}"
PODMAN_MEMORY_MB="${PODMAN_MEMORY_MB:-6144}"
PODMAN_DISK_GB="${PODMAN_DISK_GB:-40}"
INSTALL_PODMAN="${INSTALL_PODMAN:-true}"
INSTALL_OPENCODE="${INSTALL_OPENCODE:-true}"
INSTALL_OPENCLAW="${INSTALL_OPENCLAW:-false}"

USE_DEFAULTS=false
OLLAMA_BIN=""    # resolved during preflight

# ──────────────────────────────────────────────────────────────
# COLORS & STRUCTURED LOGGING
# ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

_ts()    { date '+%H:%M:%S'; }
info()   { echo -e "${CYAN}[$(_ts) INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[$(_ts)]  ✓${NC}  $*"; }
warn()   { echo -e "${YELLOW}[$(_ts) WARN]${NC}  $*"; }
step()   { echo -e "\n${BOLD}${BLUE}━━ $* ${NC}"; }
die() {
  echo -e "\n${RED}[$(_ts) FAIL]${NC}  $*" >&2
  echo -e "${DIM}  Tip: run './setup.sh doctor' to diagnose issues${NC}" >&2
  exit 1
}
# Log to file silently (for long-running operations)
flog() {
  local svc="$1"; shift
  echo "[$(_ts)] $*" >> "${LOG_DIR}/${svc}.log" 2>/dev/null || true
}

# ──────────────────────────────────────────────────────────────
# GUM — interactive TUI (install if missing, fallback to read)
# ──────────────────────────────────────────────────────────────
GUM_BIN=""
ensure_gum() {
  if command -v gum &>/dev/null; then
    GUM_BIN="$(command -v gum)"
    return
  fi
  if [[ -x "${BREW_PREFIX}/bin/gum" ]]; then
    GUM_BIN="${BREW_PREFIX}/bin/gum"
    return
  fi
  info "Installing gum (TUI library for interactive prompts)..."
  "$BREW_BIN" install gum 2>&1 | tail -1 \
    || { warn "gum install failed — falling back to plain 'read' prompts."; return; }
  GUM_BIN="${BREW_PREFIX}/bin/gum"
  ok "gum installed: $GUM_BIN"
}

# spin_run <title> <cmd> [args...]
# Runs a command with a spinner (or plain info if no TTY / no gum)
spin_run() {
  local title="$1"; shift
  mkdir -p "$LOG_DIR"
  local logfile="${LOG_DIR}/last_op.log"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] $title: $*"
    return 0
  fi

  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    if ! "$GUM_BIN" spin --spinner dot --title "  ${title}..." -- "$@" >"$logfile" 2>&1; then
      echo -e "${RED}  ✗ ${title}${NC}"
      cat "$logfile"
      return 1
    fi
    echo -e "${GREEN}  ✓ ${title}${NC}"
  else
    info "$title..."
    if ! "$@" >"$logfile" 2>&1; then
      echo -e "${RED}  ✗ ${title}${NC}"
      cat "$logfile"
      return 1
    fi
    ok "$title"
  fi
}

# sys_exec <cmd> [args...]
# Executes a command that mutates system state (or skips it if DRY_RUN=true)
sys_exec() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Exec: $*"
    return 0
  fi
  "$@"
}

# file_write <target_file>
# Reads from stdin and writes to target_file, or just prints info if DRY_RUN=true
file_write() {
  local target_file="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would generate file: $target_file"
    cat > /dev/null
  else
    cat > "$target_file"
  fi
}

# file_tee <target_file>
# Reads from stdin, writes to stdout and target_file, or just prints info if DRY_RUN=true
file_tee() {
  local target_file="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would generate file via sudo tee: $target_file"
    cat > /dev/null
  else
    sudo tee "$target_file" > /dev/null
  fi
}

# ask <var_name> <prompt_label> <default_value> [required=false]
# Sets variable via gum input or read fallback.
# Skips if: env var pre-set, or USE_DEFAULTS=true (and not required+empty)
ask() {
  local var="$1" label="$2" default="$3" required="${4:-false}"
  local cur="${!var:-}"

  # Already set via environment — don't ask (unless FORCE_MODE is on AND not in defaults mode)
  if [[ -n "$cur" ]]; then
    if [[ "$FORCE_MODE" == "false" || "$USE_DEFAULTS" == "true" ]]; then
      if [[ "$var" == "TAILSCALE_AUTHKEY" ]]; then
        info "  ${var} = *** (env)"
      else
        info "  ${var} = ${cur} (env)"
      fi
      return
    fi
  fi

  # --defaults mode: use default unless field is required and has no default
  if [[ "$USE_DEFAULTS" == "true" ]]; then
    if [[ "$required" == "true" && -z "$default" ]]; then
      : # Must still ask — fall through
    else
      printf -v "$var" '%s' "$default"
      info "  ${var} = ${default} (default)"
      return
    fi
  fi

  local val
  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    val=$(
      "$GUM_BIN" input \
        --prompt "  ${label}: " \
        --placeholder "$default" \
        --value "$default" \
        --width 70
    ) || val="$default"
  else
    printf "  %s [%s]: " "$label" "$default"
    IFS= read -r val
  fi
  printf -v "$var" '%s' "${val:-$default}"
}

# ask_confirm <var_name> <prompt_label> <default=true|false>
ask_confirm() {
  local var="$1" label="$2" default="${3:-true}"
  local cur="${!var:-}"

  # Already set via environment — don't ask (unless FORCE_MODE is on AND not in defaults mode)
  if [[ -n "$cur" ]]; then
    if [[ "$FORCE_MODE" == "false" || "$USE_DEFAULTS" == "true" ]]; then
      info "  ${var} = ${cur} (env)"; return
    fi
  fi
  if [[ "$USE_DEFAULTS" == "true" ]]; then
    printf -v "$var" '%s' "$default"
    info "  ${var} = ${default} (default)"; return
  fi

  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    local gum_args=(--affirmative="Yes" --negative="No")
    [[ "$default" == "false" ]] && gum_args=(--default=1 "${gum_args[@]}")
    if "$GUM_BIN" confirm "${gum_args[@]}" "  $label" 2>/dev/null; then
      printf -v "$var" '%s' "true"
    else
      printf -v "$var" '%s' "false"
    fi
  else
    local yn_hint="Y/n"; [[ "$default" == "false" ]] && yn_hint="y/N"
    printf "  %s [%s]: " "$label" "$yn_hint"
    IFS= read -r yn
    case "${yn:-$([[ "$default" == true ]] && echo y || echo n)}" in
      [Yy]*) printf -v "$var" '%s' "true" ;;
      *)     printf -v "$var" '%s' "false" ;;
    esac
  fi
}

# ask_choose <var_name> <prompt_label> <option1> <option2> ...
ask_choose() {
  local var="$1" label="$2"; shift 2
  local cur="${!var:-}"
  if [[ -n "$cur" ]]; then info "  ${var} = ${cur} (env)"; return; fi
  if [[ "$USE_DEFAULTS" == "true" ]]; then
    printf -v "$var" '%s' "$1"  # first option is default
    info "  ${var} = $1 (default)"; return
  fi

  local opts=("$@") val idx
  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    val=$(printf '%s\n' "${opts[@]}" | "$GUM_BIN" choose --header "  $label" 2>/dev/null) || val="$1"
  else
    echo "  $label:"
    local i=1; for opt in "${opts[@]}"; do echo "    $i) $opt"; i=$((i+1)); done
    printf "  Choice [1]: "; IFS= read -r idx
    if [[ -z "$idx" ]]; then
      val="$1"
    elif [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -ge 1 ]] && [[ "$idx" -le "${#opts[@]}" ]]; then
      val="${opts[idx-1]}"
    else
      val="$1"
    fi
  fi
  printf -v "$var" '%s' "${val:-$1}"
}

# ──────────────────────────────────────────────────────────────
# MANIFEST — tracks every artifact for atomic uninstall
# ──────────────────────────────────────────────────────────────
manifest_init() {
  mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$DATA_DIR" "$WRAPPER_DIR" \
           "${HOME}/Library/LaunchAgents" || die "Cannot create config dirs."
  [[ -f "$MANIFEST" ]] || touch "$MANIFEST"
}

manifest_add() {
  local type="$1" path="$2"
  grep -qxF "${type}:${path}" "$MANIFEST" 2>/dev/null || echo "${type}:${path}" >> "$MANIFEST"
}

manifest_entries_of_type() {
  local type="$1"
  grep "^${type}:" "$MANIFEST" 2>/dev/null | cut -d: -f2-
}

# ──────────────────────────────────────────────────────────────
# DNS SAFETY UTILITIES
# ──────────────────────────────────────────────────────────────
snapshot_dns() {
  info "Snapshotting current DNS state (for safety restore)..."
  mkdir -p "$CONFIG_DIR"
  scutil --dns > "${CONFIG_DIR}/dns_snapshot.txt" 2>/dev/null || true
  # Per-interface DNS (Wi-Fi + Ethernet)
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r svc; do
    local safe_key
    safe_key="${svc//[^a-zA-Z0-9]/_}"
    networksetup -getdnsservers "$svc" > "${CONFIG_DIR}/dns_${safe_key}.txt" 2>/dev/null || true
  done
  manifest_add "file" "${CONFIG_DIR}/dns_snapshot.txt"
  ok "DNS state saved to ${CONFIG_DIR}/dns_snapshot.txt"
}

check_internet() {
  local label="${1:-Internet connectivity}"
  # Test 1: raw IP (no DNS) — proves routing works
  curl -sf --max-time 8 --connect-timeout 5 https://1.1.1.1 -o /dev/null || return 1
  # Test 2: DNS resolution
  nslookup google.com 8.8.8.8 &>/dev/null || return 1
  ok "$label: OK"
}

# ──────────────────────────────────────────────────────────────
# PHASE 0: PRE-VALIDATION (zero system changes)
# All checks run here before any files are touched
# ──────────────────────────────────────────────────────────────
phase_validate() {
  step "Pre-validation (no system changes)"

  # macOS only
  [[ "$(uname)" == "Darwin" ]] || die "This script targets macOS only."

  # Not root
  [[ $EUID -ne 0 ]] || die "Do NOT run as root. Script elevates via 'sudo' only where needed."

  # macOS 12+
  [[ "$MACOS_MAJOR" -ge 12 ]] || die "macOS 12 (Monterey) or later required. Current: $MACOS_VER"

  # Homebrew
  [[ -x "$BREW_BIN" ]] || die \
    "Homebrew not found.\n  Install: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

  # Sandbox check
  if [[ "$ENABLE_SANDBOX" == "true" ]]; then
    if [[ ! -x "/usr/bin/sandbox-exec" ]]; then
      die "/usr/bin/sandbox-exec not found or not executable.\n  Apple may have removed it. Set ENABLE_SANDBOX=false to bypass."
    fi
  fi

  # Ollama
  if command -v ollama &>/dev/null; then
    OLLAMA_BIN="$(command -v ollama)"
  elif [[ -x "${BREW_PREFIX}/bin/ollama" ]]; then
    OLLAMA_BIN="${BREW_PREFIX}/bin/ollama"
  else
    die "Ollama not found.\n  Download: https://ollama.com/download/mac\n  Or: brew install ollama"
  fi
  # Strip quarantine flag to prevent Gatekeeper popups
  xattr -d com.apple.quarantine "$OLLAMA_BIN" 2>/dev/null || true

  # Disk space (need at least 5 GB free)
  local free_gb
  free_gb=$(df -g "$HOME" | awk 'NR==2{print $4}')
  [[ "$free_gb" -ge 5 ]] || die "Less than 5 GB free disk space (${free_gb} GB available)."

  # Port availability
  if lsof -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN &>/dev/null; then
    if lsof -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN | grep -qi "ollama"; then
      warn "Ollama is already running on port ${OLLAMA_PORT}. Terminating to allow clean install..."
      # Prevent auto-respawn if running via macOS App or Homebrew
      osascript -e 'quit app "Ollama"' 2>/dev/null || true
      if command -v brew >/dev/null; then
        brew services stop ollama 2>/dev/null || true
      fi
      launchctl unload "$PLIST_OLLAMA" 2>/dev/null || true
      local ollama_pids
      ollama_pids=$(lsof -t -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN)
      if [[ -n "$ollama_pids" ]]; then
        while IFS= read -r pid; do
          if [[ -n "$pid" ]]; then
            kill -9 "$pid" 2>/dev/null || true
          fi
        done <<< "$ollama_pids"
      fi
      sleep 2
      if lsof -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN &>/dev/null; then
        warn "Port ${OLLAMA_PORT} is still in use after attempting to terminate Ollama."
        lsof -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN | head -3
        die "Free port ${OLLAMA_PORT} before installing, or set OLLAMA_PORT=<other>"
      fi
    else
      warn "Port ${OLLAMA_PORT} is already in use by another application."
      lsof -iTCP:"${OLLAMA_PORT}" -sTCP:LISTEN | head -3
      die "Free port ${OLLAMA_PORT} before installing, or set OLLAMA_PORT=<other>"
    fi
  fi

  # Internet connectivity before any changes
  check_internet "Pre-install internet" || die \
    "No internet connectivity before install.\n  Check your network connection and try again."

  # sudo access check (non-destructive touch)
  sudo -n true 2>/dev/null || {
    info "This script needs sudo for system daemon setup. You will be prompted once."
    sudo true || die "sudo access is required."
  }

  ok "All pre-validation checks passed."
  ok "Architecture:  ${ARCH} $([[ $IS_APPLE_SILICON == true ]] && echo "(Apple Silicon — Metal GPU ✓)" || echo "(Intel — CPU inference)")"
  ok "macOS:         ${MACOS_VER}"
  ok "Homebrew:      ${BREW_PREFIX}"
  ok "Ollama binary: ${OLLAMA_BIN}"
  ok "Free disk:     ${free_gb} GB"
}

# ──────────────────────────────────────────────────────────────
# PHASE 1: INTERACTIVE CONFIGURATION
# ──────────────────────────────────────────────────────────────
phase_configure() {
  step "Configuration"

  if [[ -n "$GUM_BIN" && -t 1 && "$USE_DEFAULTS" == "false" ]]; then
    "$GUM_BIN" style \
      --foreground 212 --border-foreground 212 --border rounded \
      --align center --width 60 --padding "0 2" \
      "setup.sh v${DEVNET_VERSION} — Configuration" \
      "Press ENTER to accept defaults · Ctrl+C to abort" 2>/dev/null || true
    echo ""
  fi

  # ── Required ──────────────────────────────────────────────
  # Read .authkey securely if present in current directory
  if [[ -z "$TAILSCALE_AUTHKEY" ]] && [[ -f "$(dirname "$0")/.authkey" ]]; then
    TAILSCALE_AUTHKEY="$(tr -d '[:space:]' < "$(dirname "$0")/.authkey")"
    ok "Loaded Tailscale authkey from $(dirname "$0")/.authkey file."
  fi

  ask TAILSCALE_AUTHKEY \
    "Tailscale Auth Key (tskey-auth-XXXX) — get at tailscale.com/admin/settings/keys" \
    "" "true"

  # Validate auth key format
  [[ "$TAILSCALE_AUTHKEY" == tskey-auth-* || "$TAILSCALE_AUTHKEY" == tskey-* ]] || \
    die "Invalid auth key format: '${TAILSCALE_AUTHKEY}'\n  Must start with 'tskey-auth-'. Get one at https://login.tailscale.com/admin/settings/keys"

  # ── Tailscale ─────────────────────────────────────────────
  ask TAILSCALE_HOSTNAME "Tailscale hostname for this machine" "$TAILSCALE_HOSTNAME"
  [[ "$TAILSCALE_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]] || \
    die "Hostname '${TAILSCALE_HOSTNAME}' is invalid. Use only letters, digits, hyphens."
  ask_confirm ENABLE_TAILSCALE_SSH "Enable Tailscale SSH (remote management via tailnet)?" "$ENABLE_TAILSCALE_SSH"

  # ── Ollama ────────────────────────────────────────────────
  ask OLLAMA_PORT          "Ollama API port"           "$OLLAMA_PORT"
  ask OLLAMA_HOME          "Ollama model storage dir"  "$OLLAMA_HOME"
  
  # Set default origins if not provided (use current port)
  [[ -z "$OLLAMA_ORIGINS" ]] && OLLAMA_ORIGINS="http://127.0.0.1:${OLLAMA_PORT},http://localhost:${OLLAMA_PORT}"
  ask OLLAMA_ORIGINS       "Allowed CORS origins"      "$OLLAMA_ORIGINS"
  ask OLLAMA_NUM_PARALLEL  "Max parallel requests"     "$OLLAMA_NUM_PARALLEL"
  ask OLLAMA_MAX_LOADED_MODELS "Max loaded models in memory" "$OLLAMA_MAX_LOADED_MODELS"
  ask OLLAMA_KEEP_ALIVE    "Model keep-alive timeout"  "$OLLAMA_KEEP_ALIVE"

  # ── Performance (Apple Silicon only) ─────────────────────
  if [[ "$IS_APPLE_SILICON" == "true" ]]; then
    local total_ram_gb
    total_ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    ask GPU_MEMORY_PERCENT \
      "% of unified RAM for Metal GPU (total: ${total_ram_gb}GB)" \
      "$GPU_MEMORY_PERCENT"
  fi

  # ── Security ──────────────────────────────────────────────
  ask_confirm ENABLE_SANDBOX \
    "Enable Ollama filesystem sandbox (restricts model process to ${OLLAMA_HOME} only)?" \
    "true"

  if [[ "$ENABLE_SANDBOX" == "true" ]]; then
    warn "Sandbox uses macOS sandbox-exec. It is marked deprecated in man pages"
    warn "but remains fully functional on macOS 12–15. Models are the ONLY files"
    warn "the Ollama process can write. SSH keys, Documents etc. are inaccessible."
  fi

  # ── OpenCode & AI Agent Stack ─────────────────────────────
  ask_confirm INSTALL_OPENCODE \
    "Install and configure OpenCode harness (oh-my-opencode, fallback handling)?" \
    "$INSTALL_OPENCODE"
  
  if [[ "$INSTALL_OPENCODE" == "true" ]]; then
    ask_confirm INSTALL_OPENCLAW \
      "Install OpenClaw as an optional agent alternative?" \
      "$INSTALL_OPENCLAW"
  fi

  # ── Podman ────────────────────────────────────────────────
  ask_confirm INSTALL_PODMAN \
    "Set up Podman dev sandbox (isolated Linux VM, cannot access model files)?" \
    "true"

  if [[ "$INSTALL_PODMAN" == "true" ]]; then
    local total_cores
    total_cores=$(sysctl -n hw.logicalcpu)
    ask PODMAN_MACHINE_NAME "Podman machine name"         "$PODMAN_MACHINE_NAME"
    ask PODMAN_CPUS         "Podman VM CPUs (max: ${total_cores})" "$PODMAN_CPUS"
    ask PODMAN_MEMORY_MB    "Podman VM memory (MB)"       "$PODMAN_MEMORY_MB"
    ask PODMAN_DISK_GB      "Podman VM disk (GB)"         "$PODMAN_DISK_GB"
  fi

  # ── Review ────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}  Configuration Summary${NC}"
  echo -e "  ─────────────────────────────────────────────"
  printf "  %-30s %s\n" "Tailscale hostname:"     "$TAILSCALE_HOSTNAME"
  printf "  %-30s %s\n" "Ollama port:"            "$OLLAMA_PORT"
  printf "  %-30s %s\n" "Ollama model dir:"       "$OLLAMA_HOME"
  printf "  %-30s %s\n" "CORS Origins:"           "$OLLAMA_ORIGINS"
  printf "  %-30s %s\n" "Parallel requests:"      "$OLLAMA_NUM_PARALLEL"
  printf "  %-30s %s\n" "Max loaded models:"      "$OLLAMA_MAX_LOADED_MODELS"
  [[ $IS_APPLE_SILICON == true ]] && \
    printf "  %-30s %s\n" "Metal GPU memory:"     "${GPU_MEMORY_PERCENT}% of RAM"
  printf "  %-30s %s\n" "Filesystem sandbox:"     "$ENABLE_SANDBOX"
  printf "  %-30s %s\n" "Podman dev sandbox:"     "$INSTALL_PODMAN"
  [[ $INSTALL_PODMAN == true ]] && {
    printf "  %-30s %s\n" "Podman VM:"            "${PODMAN_CPUS} CPUs / ${PODMAN_MEMORY_MB}MB / ${PODMAN_DISK_GB}GB"
  }
  echo -e "  ─────────────────────────────────────────────\n"

  ask_confirm "_PROCEED" "Proceed with installation?" "true"
  [[ "${_PROCEED:-true}" == "true" ]] || { info "Aborted by user."; exit 0; }
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 1/7 — DEPENDENCIES
# ──────────────────────────────────────────────────────────────
step_install_deps() {
  step "1/7 — Dependencies"

  local to_install=()
  command -v tailscale &>/dev/null || to_install+=("tailscale")
  [[ "$INSTALL_PODMAN" == "true" ]] && ! command -v podman &>/dev/null && to_install+=("podman")

  if [[ ${#to_install[@]} -gt 0 ]]; then
    # NEVER run brew with sudo — preserves ownership
    spin_run "Installing ${to_install[*]} via brew (no sudo)" \
      "$BREW_BIN" install --formula "${to_install[@]}" \
      || die "brew install failed. Check: cat ${LOG_DIR}/last_op.log"
    manifest_add "brew_formula" "${to_install[*]}"
  else
    ok "All dependencies already installed."
  fi

  command -v tailscale &>/dev/null || die "tailscale not found after install."
  ok "tailscale: $(tailscale version | head -1)"
  [[ "$INSTALL_PODMAN" == "true" ]] && ok "podman: $(podman --version)"
  [[ "$INSTALL_OPENCODE" == "true" ]] && ok "node: $(node --version)"
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 2/7 — SECURITY HARDENING + OLLAMA SANDBOX
# ──────────────────────────────────────────────────────────────
step_harden_security() {
  step "2/7 — Security hardening"

  # ── Model directory: owner-only access ───────────────────
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] mkdir -p ${OLLAMA_HOME}/models"
    info "[DRY-RUN] chmod 700 ${OLLAMA_HOME}"
    info "[DRY-RUN] chmod +a \"everyone deny...\" ${OLLAMA_HOME}"
  else
    mkdir -p "${OLLAMA_HOME}/models" || die "Cannot create ${OLLAMA_HOME}"
    chmod 700 "$OLLAMA_HOME" \
      || die "Cannot chmod 700 ${OLLAMA_HOME}"
    chmod 700 "${OLLAMA_HOME}/models" 2>/dev/null || true

    # macOS ACL: explicitly deny all other users/processes
    if chmod +a "everyone deny read,write,execute,delete,append,\
readattr,writeattr,readextattr,writeextattr,readsecurity" \
      "$OLLAMA_HOME" 2>/dev/null; then
      ok "macOS ACL applied to ${OLLAMA_HOME}"
    else
      warn "ACL not supported on this volume — chmod 700 still protects it."
    fi
  fi

  manifest_add "permission" "$OLLAMA_HOME"
  ok "Model dir secured: ${OLLAMA_HOME} (mode 700, ACL: deny everyone else)"

  # ── Ollama filesystem sandbox profile ────────────────────
  if [[ "$ENABLE_SANDBOX" == "true" ]]; then
    _write_sandbox_profile
    ok "Sandbox profile written: ${SANDBOX_PROFILE}"
    ok "Ollama process may ONLY write to: ${OLLAMA_HOME}"
    ok "Protected from sandbox: ~/.ssh, ~/.aws, ~/Documents, keychains, browsers"
  fi
}

_write_sandbox_profile() {
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$DATA_DIR"
  fi

  # Build the profile with real paths substituted in
  file_write "$SANDBOX_PROFILE" <<SBPROFILE
;; setup.sh Ollama Sandbox Profile v${DEVNET_VERSION}
;; Restricts the Ollama inference process to only access its model directory.
;; sandbox-exec is deprecated in man pages but remains functional on macOS 12-15.
;; Default: DENY everything, then whitelist only what Ollama strictly needs.

(version 1)
(deny default)

;; ── Process ───────────────────────────────────────────────
(allow process-exec)
(allow process-exec-interpreter)
(allow process-fork)
(allow process-info-pidinfo)
(allow process-info-setcontrol (target self))
(allow process-info-dirtycontrol (target self))
(allow signal (target self))
(allow sysctl-read)

;; ── System libraries and frameworks (read-only) ───────────
(allow file-read*
    (subpath "/usr/lib")
    (subpath "/usr/share/zoneinfo")
    (subpath "/System/Library")
    (subpath "/Library/Frameworks")
    (subpath "/Library/Apple")
    (subpath "/private/var/db/dyld")
    (subpath "/private/var/db/timezone")
    (subpath "/private/etc")
    (literal "/dev/urandom")
    (literal "/dev/random")
    (literal "/dev/null")
    (literal "/dev/zero"))

;; ── Homebrew prefix (binaries, libs) ─────────────────────
(allow file-read* (subpath "${BREW_PREFIX}"))

;; ── OLLAMA_HOME — THE ONLY WRITABLE LOCATION ─────────────
(allow file-read* file-write* (subpath "${OLLAMA_HOME}"))

;; ── Temp / runtime dirs ───────────────────────────────────
(allow file-read* file-write*
    (subpath "/private/tmp")
    (regex #"^/private/var/folders/"))

;; ── Metal GPU (Apple Silicon) ─────────────────────────────
(allow iokit-open)
(allow mach-lookup)
(allow mach-per-user-lookup)

;; ── Network: bind to localhost only ──────────────────────
;; The OLLAMA_HOST env var enforces this at the app level too.
(allow network-bind   (local ip "127.0.0.1:${OLLAMA_PORT}"))
(allow network-inbound (local ip "127.0.0.1:${OLLAMA_PORT}"))
(allow network-outbound) ;; Required for model pulls from ollama.com

;; ── EXPLICIT DENY (belt+suspenders over default deny) ─────
;; Sensitive locations Ollama must never access
(deny file-read* file-write*
    (subpath "${HOME}/.ssh")
    (subpath "${HOME}/.gnupg")
    (subpath "${HOME}/.aws")
    (subpath "${HOME}/.config/gh")
    (subpath "${HOME}/Documents")
    (subpath "${HOME}/Desktop")
    (subpath "${HOME}/Downloads")
    (subpath "${HOME}/Library/Keychains")
    (subpath "${HOME}/Library/Safari")
    (subpath "${HOME}/Library/Cookies")
    (subpath "${HOME}/Library/Application Support/Google/Chrome")
    (subpath "${HOME}/Library/Application Support/Firefox"))
SBPROFILE

  if [[ "$DRY_RUN" != "true" ]]; then
    chmod 600 "$SANDBOX_PROFILE"
  fi
  manifest_add "file" "$SANDBOX_PROFILE"
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 3/7 — METAL GPU MEMORY (Apple Silicon only)
# ──────────────────────────────────────────────────────────────
step_setup_gpu_memory() {
  if [[ "$IS_APPLE_SILICON" != "true" ]]; then
    ok "Intel Mac — Metal GPU step skipped."
    return
  fi

  step "3/7 — Metal GPU memory optimization"

  local total_ram_mb gpu_mb
  total_ram_mb=$(( $(sysctl -n hw.memsize) / 1048576 ))
  gpu_mb=$(( total_ram_mb * GPU_MEMORY_PERCENT / 100 ))

  info "RAM: ${total_ram_mb}MB | Allocating ${gpu_mb}MB (${GPU_MEMORY_PERCENT}%) to Metal GPU"

  # Apply immediately (non-destructive sysctl)
  sys_exec sudo sysctl iogpu.wired_limit_mb="${gpu_mb}" > /dev/null \
    || die "sysctl iogpu.wired_limit_mb failed."

  # Write persistent wrapper script
  local gpu_wrapper="${WRAPPER_DIR}/set-gpu-memory.sh"
  file_write "$gpu_wrapper" <<SCRIPT
#!/bin/bash
# setup.sh: Set Metal GPU memory at boot
TOTAL_MB=\$(( \$(sysctl -n hw.memsize) / 1048576 ))
GPU_MB=\$(( TOTAL_MB * ${GPU_MEMORY_PERCENT} / 100 ))
/usr/sbin/sysctl iogpu.wired_limit_mb=\${GPU_MB}
echo "\$(date '+%F %T'): Metal GPU = \${GPU_MB}MB (${GPU_MEMORY_PERCENT}% of \${TOTAL_MB}MB)" >> "${LOG_DIR}/gpu-memory.log"
SCRIPT
  if [[ "$DRY_RUN" != "true" ]]; then
    chmod +x "$gpu_wrapper"
  fi

  file_tee "$PLIST_GPU_DAEMON" > /dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.${DEVNET_NAME}.gpu-memory</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${gpu_wrapper}</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>StandardOutPath</key><string>${LOG_DIR}/gpu-memory.log</string>
    <key>StandardErrorPath</key><string>${LOG_DIR}/gpu-memory.log</string>
</dict>
</plist>
PLIST

  sys_exec sudo launchctl unload  "$PLIST_GPU_DAEMON" 2>/dev/null || true
  sys_exec sudo launchctl load -w "$PLIST_GPU_DAEMON" \
    || die "Failed to load GPU memory LaunchDaemon."

  manifest_add "launchdaemon" "$PLIST_GPU_DAEMON"
  manifest_add "file"         "$gpu_wrapper"
  ok "Metal GPU: ${gpu_mb}MB allocated (persists on reboot)"
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 4/7 — TAILSCALE SYSTEM DAEMON
# Uses --accept-dns=false to guarantee internet is never broken
# ──────────────────────────────────────────────────────────────
step_setup_tailscale() {
  step "4/7 — Tailscale system daemon (--accept-dns=false)"

  # Locate tailscaled binary
  local ts_daemon="${BREW_PREFIX}/opt/tailscale/bin/tailscaled"
  [[ -x "$ts_daemon" ]] || ts_daemon="${BREW_PREFIX}/bin/tailscaled"
  [[ -x "$ts_daemon" ]] || die "tailscaled binary not found at ${ts_daemon}"

  # Snapshot DNS state before any Tailscale interaction
  snapshot_dns

  # Kill any stale tailscaled
  sys_exec sudo pkill tailscaled 2>/dev/null || true
  if [[ "$DRY_RUN" != "true" ]]; then
    sleep 1
    sudo mkdir -p /var/db/tailscale /var/run/tailscale
  fi

  file_tee "$PLIST_TS_DAEMON" > /dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.${DEVNET_NAME}.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>${ts_daemon}</string>
        <string>-state</string>
        <string>/var/db/tailscale/tailscaled.state</string>
        <string>-socket</string>
        <string>/var/run/tailscale/tailscaled.sock</string>
        <string>-port</string>
        <string>41641</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>${LOG_DIR}/tailscaled.log</string>
    <key>StandardErrorPath</string><string>${LOG_DIR}/tailscaled.log</string>
</dict>
</plist>
PLIST

  sys_exec sudo launchctl unload  "$PLIST_TS_DAEMON" 2>/dev/null || true
  sys_exec sudo launchctl load -w "$PLIST_TS_DAEMON" \
    || die "Failed to load Tailscale LaunchDaemon.\n  Check: sudo cat ${LOG_DIR}/tailscaled.log"
  
  if [[ "$DRY_RUN" != "true" ]]; then
    sleep 3
    pgrep tailscaled &>/dev/null \
      || die "tailscaled failed to start.\n  Check: sudo tail -30 ${LOG_DIR}/tailscaled.log"
  fi
  ok "tailscaled is running."

  # ── Authenticate headlessly ───────────────────────────────
  # --accept-dns=false: prevents any DNS override, guaranteed safe internet
  # --accept-routes=false: don't accept subnet routes (not needed, safer)
  # --ssh: enable Tailscale SSH for remote management (if enabled)
  info "Authenticating with Tailscale (headless, no browser, no notifications)..."
  local ts_up_args=(
    --auth-key="${TAILSCALE_AUTHKEY}"
    --hostname="${TAILSCALE_HOSTNAME}"
    --accept-dns=false
    --accept-routes=false
    --reset
  )
  [[ "$ENABLE_TAILSCALE_SSH" == "true" ]] && ts_up_args+=(--ssh)

  sys_exec sudo tailscale up "${ts_up_args[@]}" \
    || die "tailscale up failed.\n  Verify your auth key is Reusable + Pre-approved at:\n  https://login.tailscale.com/admin/settings/keys"
  [[ "$DRY_RUN" != "true" ]] && sleep 5

  # ── Internet verification AFTER auth ─────────────────────
  info "Verifying internet is intact after Tailscale connection..."
  if [[ "$DRY_RUN" != "true" ]] && ! check_internet "Post-Tailscale internet"; then
    # Auto-recover: disable Tailscale DNS (belt + suspenders over --accept-dns=false)
    warn "Internet check failed — running additional DNS recovery..."
    sudo tailscale set --accept-dns=false 2>/dev/null || true
    sleep 2
    check_internet "Post-recovery internet" \
      || die "Internet broken after Tailscale setup.\n  Recovery: sudo tailscale down\n  DNS restore: scutil --set HostName '$(hostname)'"
  fi

  # Get and persist the Tailscale IP
  local ts_ip
  if [[ "$DRY_RUN" == "true" ]]; then
    ts_ip="100.x.y.z"
  else
    ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
    [[ -z "$ts_ip" ]] && die "No Tailscale IP assigned.\n  Verify auth key at: https://login.tailscale.com/admin/machines"
    echo "$ts_ip" > "${CONFIG_DIR}/tailscale_ip"
  fi

  manifest_add "launchdaemon" "$PLIST_TS_DAEMON"
  manifest_add "file"         "${CONFIG_DIR}/tailscale_ip"
  ok "Tailscale authenticated → Tailnet IP: ${ts_ip}"
  ok "DNS: NOT delegated to Tailscale (--accept-dns=false) — internet protected"
  tailscale status
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 5/7 — OLLAMA HOST SERVICE (LaunchAgent + sandbox)
# ──────────────────────────────────────────────────────────────
step_setup_ollama() {
  step "5/7 — Ollama host service (Metal GPU, sandbox-hardened)"

  # Kill any existing instance cleanly
  pkill -f "ollama serve" 2>/dev/null || true
  pkill -f "Ollama"       2>/dev/null || true
  sleep 2

  # Set env vars in launchctl session layer (affects all subsequent GUI processes)
  launchctl setenv OLLAMA_HOST    "127.0.0.1:${OLLAMA_PORT}"
  launchctl setenv OLLAMA_ORIGINS "$OLLAMA_ORIGINS"
  launchctl setenv OLLAMA_HOME    "${OLLAMA_HOME}"

  # Hardware-specific performance flags
  local hw_env=""
  if [[ "$IS_APPLE_SILICON" == "true" ]]; then
    hw_env="
        <key>OLLAMA_NUM_GPU</key><string>999</string>
        <key>OLLAMA_FLASH_ATTENTION</key><string>1</string>
        <key>OLLAMA_KV_CACHE_TYPE</key><string>q8_0</string>"
  else
    local cpu_cores
    cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)
    hw_env="
        <key>OLLAMA_NUM_THREAD</key><string>${cpu_cores}</string>"
  fi

  # ProgramArguments: wrap with sandbox-exec if enabled
  local prog_args
  if [[ "$ENABLE_SANDBOX" == "true" ]]; then
    prog_args="
        <string>/usr/bin/sandbox-exec</string>
        <string>-f</string>
        <string>${SANDBOX_PROFILE}</string>
        <string>${OLLAMA_BIN}</string>
        <string>serve</string>"
  else
    prog_args="
        <string>${OLLAMA_BIN}</string>
        <string>serve</string>"
  fi

  file_write "$PLIST_OLLAMA" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.${DEVNET_NAME}.ollama</string>

    <key>ProgramArguments</key>
    <array>${prog_args}
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <!-- SECURITY: loopback only — LAN/internet cannot reach Ollama directly -->
        <key>OLLAMA_HOST</key><string>127.0.0.1:${OLLAMA_PORT}</string>
        <key>OLLAMA_ORIGINS</key><string>${OLLAMA_ORIGINS}</string>
        <key>OLLAMA_HOME</key><string>${OLLAMA_HOME}</string>

        <!-- Performance -->
        <key>OLLAMA_NUM_PARALLEL</key><string>${OLLAMA_NUM_PARALLEL}</string>
        <key>OLLAMA_MAX_LOADED_MODELS</key><string>${OLLAMA_MAX_LOADED_MODELS}</string>
        <key>OLLAMA_KEEP_ALIVE</key><string>${OLLAMA_KEEP_ALIVE}</string>
        ${hw_env}

        <!-- Runtime -->
        <key>HOME</key><string>${HOME}</string>
        <key>PATH</key><string>${BREW_PREFIX}/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>

    <!-- Start immediately; restart only on crash, not clean exit -->
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key><true/>
        <key>SuccessfulExit</key><false/>
    </dict>
    <!-- Prevent restart storms: 15s cooldown between restarts -->
    <key>ThrottleInterval</key><integer>15</integer>

    <!-- Interactive priority (needed for Metal GPU scheduling) -->
    <key>ProcessType</key><string>Interactive</string>

    <key>StandardOutPath</key><string>${LOG_DIR}/ollama.log</string>
    <key>StandardErrorPath</key><string>${LOG_DIR}/ollama.error.log</string>
</dict>
</plist>
PLIST

  sys_exec launchctl unload  "$PLIST_OLLAMA" 2>/dev/null || true
  sys_exec launchctl load -w "$PLIST_OLLAMA" \
    || die "Failed to load Ollama LaunchAgent.\n  Check: cat ${PLIST_OLLAMA}"

  # Health check with retries
  info "Waiting for Ollama API to respond..."
  local attempts=0
  if [[ "$DRY_RUN" != "true" ]]; then
    until curl -sf "http://127.0.0.1:${OLLAMA_PORT}/api/tags" -o /dev/null; do
      attempts=$((attempts + 1))
      if [[ $attempts -ge 15 ]]; then
        echo ""
        die "Ollama did not respond after 45s.\n  Check: tail -50 ${LOG_DIR}/ollama.error.log"
      fi
      [[ "$((attempts % 3))" -eq 0 ]] && warn "  Attempt ${attempts}/15..."
      sleep 3
    done
  fi

  manifest_add "launchagent" "$PLIST_OLLAMA"
  ok "Ollama live on 127.0.0.1:${OLLAMA_PORT}"
  [[ "$ENABLE_SANDBOX" == "true" ]] && ok "Sandbox: Ollama filesystem access restricted to ${OLLAMA_HOME}"
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 6/7 — TAILSCALE SERVE (sole external proxy)
# ──────────────────────────────────────────────────────────────
step_setup_tailscale_serve() {
  step "6/7 — Tailscale Serve (authenticated reverse proxy)"

  # Reset any stale serve config
  sys_exec tailscale serve reset 2>/dev/null || true

  # Proxy tailnet → localhost Ollama (HTTPS with auto cert via Tailscale)
  sys_exec tailscale serve --bg "http://127.0.0.1:${OLLAMA_PORT}" \
    || die "tailscale serve failed.\n  Check: tailscale serve status"

  ok "Tailscale Serve active — Ollama exposed ONLY via authenticated tailnet:"
  [[ "$DRY_RUN" != "true" ]] && tailscale serve status
}

# ──────────────────────────────────────────────────────────────
# INSTALL: 7/7 — PODMAN DEV SANDBOX
# ──────────────────────────────────────────────────────────────
step_setup_podman() {
  if [[ "$INSTALL_PODMAN" != "true" ]]; then
    ok "Podman setup skipped (INSTALL_PODMAN=false)."
    return
  fi

  step "7/7 — Podman development sandbox"

  local podman_bin="${BREW_PREFIX}/bin/podman"

  # Remove stale stopped machine
  if "$podman_bin" machine list --format '{{.Name}}' 2>/dev/null | grep -q "^${PODMAN_MACHINE_NAME}$"; then
    local is_running
    is_running=$("$podman_bin" machine list --format '{{.Name}} {{.Running}}' \
      | awk -v m="$PODMAN_MACHINE_NAME" '$1==m{print $2}')
    if [[ "$is_running" == "true" ]]; then
      ok "Podman machine '${PODMAN_MACHINE_NAME}' already running — skipping init."
    else
      warn "Removing stale machine '${PODMAN_MACHINE_NAME}'..."
      "$podman_bin" machine rm -f "$PODMAN_MACHINE_NAME" 2>/dev/null || true
    fi
  fi

  if ! "$podman_bin" machine list --format '{{.Name}}' 2>/dev/null | grep -q "^${PODMAN_MACHINE_NAME}$"; then
    info "Initializing Podman VM: ${PODMAN_CPUS} CPUs | ${PODMAN_MEMORY_MB}MB | ${PODMAN_DISK_GB}GB"
    spin_run "Creating Podman machine (this may take 2–3 minutes)" \
      "$podman_bin" machine init \
        --cpus "$PODMAN_CPUS" \
        --memory "$PODMAN_MEMORY_MB" \
        --disk-size "$PODMAN_DISK_GB" \
        --rootful \
        --now \
        "$PODMAN_MACHINE_NAME" \
      || die "Podman machine init failed.\n  Check: cat ${LOG_DIR}/last_op.log"
  fi

  sleep 5
  ok "Podman machine '${PODMAN_MACHINE_NAME}' running."
  info "Dev containers reach Ollama via: http://host.containers.internal:${OLLAMA_PORT}"
  warn "Model files at ${OLLAMA_HOME} are NOT mounted into any container."

  # Autostart LaunchAgent for Podman machine
  local machine_wrapper="${WRAPPER_DIR}/start-podman-machine.sh"
  file_write "$machine_wrapper" <<SCRIPT
#!/bin/bash
# setup.sh: Start Podman machine on login
export HOME="${HOME}"
export PATH="${BREW_PREFIX}/bin:/usr/local/bin:/usr/bin:/bin"
LOG="${LOG_DIR}/podman-machine.log"
mkdir -p "${LOG_DIR}"
echo "\$(date '+%F %T'): Starting '${PODMAN_MACHINE_NAME}'..." >> "\$LOG"
"${podman_bin}" machine start "${PODMAN_MACHINE_NAME}" >> "\$LOG" 2>&1 \
  && echo "\$(date '+%F %T'): Started OK." >> "\$LOG" \
  || echo "\$(date '+%F %T'): Start failed or already running." >> "\$LOG"
SCRIPT
  if [[ "$DRY_RUN" != "true" ]]; then
    chmod +x "$machine_wrapper"
  fi

  file_write "$PLIST_PODMAN" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.${DEVNET_NAME}.podman-machine</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${machine_wrapper}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>${HOME}</string>
        <key>PATH</key><string>${BREW_PREFIX}/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>StandardOutPath</key><string>${LOG_DIR}/podman-launch.log</string>
    <key>StandardErrorPath</key><string>${LOG_DIR}/podman-launch.log</string>
</dict>
</plist>
PLIST

  sys_exec launchctl unload  "$PLIST_PODMAN" 2>/dev/null || true
  sys_exec launchctl load -w "$PLIST_PODMAN" \
    || die "Failed to load Podman LaunchAgent."

  manifest_add "launchagent" "$PLIST_PODMAN"
  manifest_add "file"         "$machine_wrapper"
}

# ──────────────────────────────────────────────────────────────
# STEP: OPENCODE AND AGENTIC TOOLING
# ──────────────────────────────────────────────────────────────
step_setup_opencode() {
  if [[ "$INSTALL_OPENCODE" != "true" ]]; then
    ok "OpenCode setup skipped."
    return
  fi

  step "8/9 — OpenCode & AI Agent Setup"
  
  if ! command -v npm >/dev/null; then
    warn "npm not found. Skipping OpenCode CLI installation."
    return
  fi

  local req_pkgs=(
    "oh-my-opencode"
    "opencode-pollinations-plugin"
  )
  [[ "$DRY_RUN" == "true" ]] && info "[DRY-RUN] Will npm install -g opencode ${req_pkgs[*]}"
  
  sys_exec npm install -g opencode "${req_pkgs[@]}" --silent \
    || warn "Failed to install OpenCode ecosystem."
  
  if [[ "$INSTALL_OPENCLAW" == "true" ]]; then
    sys_exec npm install -g openclaw --silent || warn "Failed to install openclaw."
  fi

  # Configure OpenCode rate-limit bypass and Ollama fallback
  local oc_dir="${HOME}/.opencode"
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$oc_dir"
  fi
  
  file_write "${oc_dir}/config.json" <<EOF
{
  "plugins": ["oh-my-opencode", "opencode-pollinations-plugin"],
  "rateLimit": {
    "bypass": true,
    "fallbackModel": "ollama",
    "fallbackUrl": "http://127.0.0.1:${OLLAMA_PORT}"
  }
}
EOF
  ok "Configured OpenCode with rate-limit bypass and Ollama fallback."

  # Install best fallback model based on RAM
  local total_ram_mb
  total_ram_mb=$(( $(sysctl -n hw.memsize) / 1048576 ))
  local fallback_model="mistral:7b"
  
  if [[ total_ram_mb -ge 32000 ]]; then
    fallback_model="mixtral:8x7b"
  elif [[ total_ram_mb -ge 16000 ]]; then
    fallback_model="llama3:8b"
  fi
  
  info "Determined best fallback model for this hardware: ${fallback_model}"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would curl pull fallback model: $fallback_model"
  else
    spin_run "Pulling Ollama fallback model ($fallback_model) in background..." \
      curl -sf -X POST "http://127.0.0.1:${OLLAMA_PORT}/api/pull" -d "{\"name\": \"${fallback_model}\"}" &
  fi
  ok "Fallback model pull initiated."
}

# ──────────────────────────────────────────────────────────────
# STEP: PODMAN DEVELOPMENT WORKSPACE (CONTAINER)
# ──────────────────────────────────────────────────────────────
step_setup_workspace() {
  if [[ "$INSTALL_PODMAN" != "true" ]]; then
    return
  fi

  step "9/9 — Standalone AI Dev Workspace (Container)"
  manifest_add "dir" "${HOME}/repos"
  
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "${HOME}/repos"
  else
    info "[DRY-RUN] Would create directory: ${HOME}/repos"
  fi
  
  local podman_bin="${BREW_PREFIX}/bin/podman"
  local dc_dir="${CONFIG_DIR}/workspace"
  
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$dc_dir"
  fi
  
  file_write "$dc_dir/Dockerfile" <<'EOF'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    curl wget git build-essential \
    python3 python3-pip python3-venv \
    nodejs npm unzip software-properties-common \
    zsh openssh-server sudo tmux

# Setup Zsh and recommended plugins
RUN sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions \${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' \${HOME}/.zshrc && \
    chsh -s \$(which zsh)

# Setup SSH daemon
RUN mkdir /var/run/sshd && \
    echo 'root:admin' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install gh -y

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install Flutter (minimal setup)
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/root/.bun/bin:/root/.cargo/bin:${PATH}"

# Configure Git safe directory
RUN git config --global --add safe.directory /workspace

# Install recommended MCPs for agentic coding
RUN npm install -g \
    @modelcontextprotocol/server-github \
    @modelcontextprotocol/server-postgres \
    @modelcontextprotocol/server-sqlite \
    @modelcontextprotocol/server-brave-search

WORKDIR /workspace
EOF

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would build 'ai-workspace' using Podman."
    return
  fi

  # Attempt to start the machine if not running yet
  "$podman_bin" machine start "$PODMAN_MACHINE_NAME" 2>/dev/null || true
  sleep 2

  if "$podman_bin" info &>/dev/null; then
    spin_run "Building 'ai-workspace' container (includes Flutter, Rust, Node, MCPs)..." \
      "$podman_bin" build -t ai-workspace "$dc_dir"
    
    # Refresh container
    "$podman_bin" rm -f ai-workspace 2>/dev/null || true
    
    # Run persistently mapping to ~/repos, starting SSH and keeping alive
    sys_exec "$podman_bin" run -dt --name ai-workspace --network host \
      -v "${HOME}/repos:/workspace" ai-workspace bash -c "service ssh start && tail -f /dev/null"
    
    ok "AI Dev Workspace is ready. Source logic bound to: ~/repos"
    info "SSH accessible remotely via Tailnet (port 2222). Default root pass: admin"

    # Create wrapper to drop into workspace
    local shell_wrapper="${WRAPPER_DIR}/workspace-shell.sh"
    file_write "$shell_wrapper" <<SCRIPT
#!/bin/bash
export PATH="\${PATH}:/opt/homebrew/bin:/usr/local/bin"
exec podman exec -it ai-workspace zsh
SCRIPT
    if [[ "$DRY_RUN" != "true" ]]; then
      chmod +x "$shell_wrapper"
    fi
  else
    warn "Cannot build Dev Container — Podman not responding or failed."
  fi
}

# ──────────────────────────────────────────────────────────────
# STEP: TAILSCALE DRIVE (Network Shared Storage)
# ──────────────────────────────────────────────────────────────
step_setup_taildrive() {
  step "10/10 — Tailscale Drive (Shared Network Storage)"
  
  if ! command -v tailscale >/dev/null; then
    warn "tailscale not found. Cannot configure Tailscale Drive."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would share Taildrive: tailscale drive share repos ${HOME}/repos"
  else
    # The 'tailscale drive' command connects directory to Tailnet
    sys_exec tailscale drive share repos "${HOME}/repos" 2>/dev/null || true
  fi
  
  ok "Shared ~/repos securely across the Tailnet via Tailscale Drive."
  info "To view across devices, ensure your Tailscale ACL has 'drive:share' enabled."
}

# ──────────────────────────────────────────────────────────────
# INSTALL: FIREWALL
# ──────────────────────────────────────────────────────────────
step_setup_firewall() {
  local fw_state
  fw_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
  if [[ "$fw_state" -ge 1 ]]; then
    warn "macOS Firewall is ON (state=${fw_state}) — auto-whitelisting Ollama binary..."
    sys_exec sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
      --add    "$OLLAMA_BIN" 2>/dev/null || true
    sys_exec sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
      --unblock "$OLLAMA_BIN" 2>/dev/null || true
    ok "Ollama unblocked in Application Firewall."
  else
    ok "Firewall is off — no action needed."
  fi
}

# ──────────────────────────────────────────────────────────────
# SAVE CONFIG SNAPSHOT
# ──────────────────────────────────────────────────────────────
save_config_snapshot() {
  file_write "$CONFIG_SNAPSHOT" <<CFG
# setup.sh config snapshot — $(date '+%F %T')
DEVNET_VERSION="${DEVNET_VERSION}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME}"
OLLAMA_PORT="${OLLAMA_PORT}"
OLLAMA_HOME="${OLLAMA_HOME}"
OLLAMA_BIN="${OLLAMA_BIN}"
ENABLE_SANDBOX="${ENABLE_SANDBOX}"
IS_APPLE_SILICON="${IS_APPLE_SILICON}"
GPU_MEMORY_PERCENT="${GPU_MEMORY_PERCENT}"
PODMAN_MACHINE_NAME="${PODMAN_MACHINE_NAME}"
INSTALL_PODMAN="${INSTALL_PODMAN}"
BREW_PREFIX="${BREW_PREFIX}"
INSTALL_DATE="$(date '+%F %T')"
CFG
  manifest_add "file" "$CONFIG_SNAPSHOT"
}

# ──────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ──────────────────────────────────────────────────────────────
print_summary() {
  local ts_ip ts_dns
  if [[ "$DRY_RUN" == "true" ]]; then
    ts_ip="100.x.y.z"
    ts_dns="${TAILSCALE_HOSTNAME}.tailnet.ts.net"
  else
    ts_ip=$(cat "${CONFIG_DIR}/tailscale_ip" 2>/dev/null || tailscale ip -4 2>/dev/null || echo "N/A")
    ts_dns=$(tailscale status --json 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); \
        print(d.get('Self',{}).get('DNSName','').rstrip('.'))" 2>/dev/null \
      || echo "${TAILSCALE_HOSTNAME}")
  fi

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║   ✅  setup.sh v${DEVNET_VERSION} — Installation Complete              ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  printf "  %-32s ${CYAN}%s${NC}\n" "Tailnet IP:"             "$ts_ip"
  printf "  %-32s ${CYAN}%s${NC}\n" "MagicDNS:"               "$ts_dns"
  printf "  %-32s ${CYAN}%s${NC}\n" "Ollama (loopback):"      "http://127.0.0.1:${OLLAMA_PORT}"
  printf "  %-32s ${CYAN}%s${NC}\n" "Ollama (tailnet HTTPS):" "https://${ts_dns}"
  printf "  %-32s ${CYAN}%s${NC}\n" "Tailscale Drive:"        "//${ts_dns}/repos"
  printf "  %-32s ${CYAN}%s${NC}\n" "Podman SSH:"             "ssh root@${ts_ip} -p 2222"
  printf "  %-32s ${CYAN}%s${NC}\n" "Model dir:"              "${OLLAMA_HOME} [mode 700]"
  printf "  %-32s ${CYAN}%s${NC}\n" "Filesystem sandbox:"     "$([[ $ENABLE_SANDBOX == true ]] && echo "enabled (sandbox-exec)" || echo "disabled")"
  [[ $IS_APPLE_SILICON == true ]] && \
    printf "  %-32s ${CYAN}%s${NC}\n" "Metal GPU memory:" "${GPU_MEMORY_PERCENT}% of RAM"
  printf "  %-32s ${CYAN}%s${NC}\n" "DNS safety:"             "--accept-dns=false (internet protected)"
  printf "  %-32s ${CYAN}%s${NC}\n" "Logs:"                   "$LOG_DIR"
  echo ""
  echo -e "  ${BOLD}📱 Mobile/remote access:${NC}"
  echo -e "     1. Install Tailscale on device → same account"
  echo -e "     2. Hit: ${CYAN}https://${ts_dns}/api/tags${NC}"
  echo ""
  echo -e "  ${BOLD}🛠  Management:${NC}"
  echo -e "     ./setup.sh status                  Live dashboard"
  echo -e "     ./setup.sh doctor                  Diagnose + auto-repair"
  echo -e "     ./setup.sh logs ollama             Tail Ollama logs"
  echo -e "     ./setup.sh stop / start            Stop or restart all"
  echo -e "     ./setup.sh uninstall               Remove all (keeps models)"
  echo -e "     ./setup.sh uninstall --purge       Remove all + logs + config"
  echo -e "     ./setup.sh reset [--defaults]      Full clean reinstall"
  echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}\n"
}

# ──────────────────────────────────────────────────────────────
# CMD: INSTALL
# ──────────────────────────────────────────────────────────────
cmd_install() {
  local idx=1
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--defaults" ]]; then
      USE_DEFAULTS=true
    elif [[ "$1" == "--dry-run" ]]; then
      DRY_RUN=true
    else
      warn "Unknown flag: $1"
    fi
    shift
  done

  if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY-RUN mode enabled. No permanent system changes will be explicitly made."
  fi

  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    "$GUM_BIN" style \
      --foreground 45 --border-foreground 45 --border double \
      --align center --width 64 --margin "1 0" --padding "1 3" \
      "setup.sh v${DEVNET_VERSION}" \
      "Enterprise macOS AI Stack" \
      "Tailscale + Ollama + Podman" 2>/dev/null || true
  fi

  manifest_init

  # Test suite explicitly runs first to validate environment 
  # (Aborts if anything is structurally broken)
  if [[ "$DRY_RUN" == "true" ]]; then
    cmd_test "dry-run"
  else
    cmd_test "install"
  fi

  # These run in order; each MUST succeed before the next starts
  phase_validate
  ensure_gum
  phase_configure
  step_install_deps
  step_harden_security
  step_setup_gpu_memory
  step_setup_tailscale
  step_setup_ollama
  step_setup_tailscale_serve
  step_setup_podman
  step_setup_opencode
  step_setup_workspace
  step_setup_taildrive
  step_setup_firewall
  save_config_snapshot
  print_summary
}

# ──────────────────────────────────────────────────────────────
# CMD: UNINSTALL (reads manifest, removes in reverse order)
# ──────────────────────────────────────────────────────────────
_run_uninstall() {
  local PURGE="${1:-false}"
  local podman_bin="${BREW_PREFIX}/bin/podman"

  # Load config snapshot to get machine name even if env not set
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi

  step "Stopping all services"

  # LaunchAgents (user-level — no sudo)
  while IFS= read -r plist; do
    info "Unloading: $plist"
    launchctl unload -w "$plist" 2>/dev/null || true
    rm -f "$plist"
  done < <(manifest_entries_of_type "launchagent" 2>/dev/null)

  # LaunchDaemons (system-level — sudo required)
  while IFS= read -r plist; do
    info "Unloading: $plist"
    sudo launchctl unload -w "$plist" 2>/dev/null || true
    sudo rm -f "$plist"
  done < <(manifest_entries_of_type "launchdaemon" 2>/dev/null)

  # Kill processes
  pkill -f "ollama serve" 2>/dev/null || true
  sudo pkill tailscaled   2>/dev/null || true
  sleep 2

  # Tailscale: disconnect gracefully, reset serve config
  tailscale serve reset                   2>/dev/null || true
  sudo tailscale down --accept-risk=all   2>/dev/null || true

  # Podman machine
  if command -v podman &>/dev/null && [[ -n "${PODMAN_MACHINE_NAME:-}" ]]; then
    spin_run "Stopping Podman machine" \
      "$podman_bin" machine stop "$PODMAN_MACHINE_NAME" 2>/dev/null || true
    spin_run "Removing Podman machine" \
      "$podman_bin" machine rm -f "$PODMAN_MACHINE_NAME" 2>/dev/null || true
  fi

  # Clear launchctl env vars
  for var in OLLAMA_HOST OLLAMA_ORIGINS OLLAMA_HOME OLLAMA_FLASH_ATTENTION OLLAMA_KV_CACHE_TYPE; do
    launchctl unsetenv "$var" 2>/dev/null || true
  done

  # Remove tracked files (wrappers, config, sandbox profile, etc.)
  while IFS= read -r file; do
    rm -f "$file" 2>/dev/null || true
  done < <(manifest_entries_of_type "file" 2>/dev/null)

  # Remove deny ACLs from model dir, keep 700 permissions
  while IFS= read -r path; do
    chmod -a "everyone deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity" "$path" 2>/dev/null || true
  done < <(manifest_entries_of_type "permission" 2>/dev/null)

  # Clean up wrappers and data dir
  rm -rf "$WRAPPER_DIR" "$DATA_DIR"

  if [[ "$PURGE" == "true" ]]; then
    warn "PURGE: Removing logs and config..."
    rm -rf "$LOG_DIR" "$CONFIG_DIR"
    warn "Model files at ${OLLAMA_HOME:-~/.ollama} preserved."
    warn "To delete models: rm -rf ${OLLAMA_HOME:-~/.ollama}"
    
    while IFS= read -r formulae; do
      info "Uninstalling brew packages: $formulae"
      "$BREW_PREFIX/bin/brew" uninstall "$formulae" 2>/dev/null || true
    done < <(manifest_entries_of_type "brew_formula" 2>/dev/null)
  else
    rm -f "$MANIFEST"
    info "Config snapshot preserved at: $CONFIG_SNAPSHOT"
    info "Logs preserved at: $LOG_DIR"
    info "Models preserved at: ${OLLAMA_HOME:-~/.ollama}"
  fi

  ok "All devnet services removed cleanly."
  echo -e "  ${DIM}Note: Metal GPU memory limit will reset to default upon reboot.${NC}"
}

cmd_uninstall() {
  local PURGE=false
  [[ "${1:-}" == "--purge" ]] && PURGE=true

  echo -e "\n${BOLD}${RED}  setup.sh — Uninstall${NC}"
  [[ "$PURGE" == "true" ]] && warn "PURGE mode: logs and config will also be deleted."
  echo ""

  [[ -f "$MANIFEST" ]] || { warn "No manifest found — nothing to uninstall."; exit 0; }

  ask_confirm "_CONFIRM_UNINSTALL" "This will stop all devnet services. Continue?" "false"
  [[ "${_CONFIRM_UNINSTALL:-false}" == "true" ]] || { info "Aborted."; exit 0; }

  ensure_gum
  _run_uninstall "$PURGE"
  echo -e "\n${GREEN}  ✅  devnet completely removed.${NC}\n"
}

# ──────────────────────────────────────────────────────────────
# CMD: RESET
# ──────────────────────────────────────────────────────────────
cmd_reset() {
  local use_defaults="${1:-}"
  echo -e "\n${BOLD}${YELLOW}  setup.sh — Reset (uninstall + fresh install)${NC}\n"
  ensure_gum

  ask_confirm "_CONFIRM_RESET" "This will uninstall then reinstall everything. Continue?" "false"
  [[ "${_CONFIRM_RESET:-false}" == "true" ]] || { info "Aborted."; exit 0; }

  if [[ -f "$MANIFEST" ]]; then
    _run_uninstall "false"
  else
    warn "No manifest — proceeding with clean install."
  fi
  sleep 2
  cmd_install "$use_defaults"
}

# ──────────────────────────────────────────────────────────────
# CMD: START / STOP
# ──────────────────────────────────────────────────────────────
cmd_start() {
  step "Starting all devnet services"
  ensure_gum
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi
  local podman_bin="${BREW_PREFIX}/bin/podman"

  sudo launchctl load -w "$PLIST_TS_DAEMON" 2>/dev/null || true
  sys_exec launchctl load -w "$PLIST_OLLAMA" 2>/dev/null || true
  if [[ "$INSTALL_PODMAN" == "true" ]]; then
    "$podman_bin" machine start "$PODMAN_MACHINE_NAME" 2>/dev/null || true
  fi
  if ! tailscale serve --bg "http://127.0.0.1:${OLLAMA_PORT}" 2>/dev/null; then
    warn "tailscale serve failed to start in bg. Run 'tailscale serve status' to diagnose."
  fi

  sleep 3
  ok "All services started."
  cmd_status
}

cmd_stop() {
  step "Stopping services (non-destructive)"
  ensure_gum
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi
  local podman_bin="${BREW_PREFIX}/bin/podman"

  sys_exec launchctl unload "$PLIST_OLLAMA" 2>/dev/null || true
  sys_exec pkill -f "ollama serve" 2>/dev/null || true
  if [[ "$INSTALL_PODMAN" == "true" ]]; then
    "$podman_bin" machine stop "$PODMAN_MACHINE_NAME" 2>/dev/null || true
  fi

  warn "Tailscale left running (other services may depend on it)."
  warn "  To stop Tailscale: sudo launchctl unload ${PLIST_TS_DAEMON}"
  ok "Ollama and Podman stopped."
}

# ──────────────────────────────────────────────────────────────
# CMD: STATUS DASHBOARD
# ──────────────────────────────────────────────────────────────
cmd_status() {
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi
  local podman_bin="${BREW_PREFIX}/bin/podman"

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   setup.sh v${DEVNET_VERSION} — Live Status Dashboard               ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}\n"

  local ts_ip="N/A" ts_dns="N/A"

  # ── Tailscale ────────────────────────────────────────────
  echo -e "${BOLD}🔒 Tailscale${NC}"
  if pgrep tailscaled &>/dev/null; then
    ts_ip=$(tailscale ip -4 2>/dev/null || echo "N/A")
    ts_dns=$(tailscale status --json 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); \
        print(d.get('Self',{}).get('DNSName','').rstrip('.'))" 2>/dev/null || echo "N/A")
    echo -e "   Status:      ${GREEN}Running ✓${NC}"
    echo -e "   Tailnet IP:  ${CYAN}${ts_ip}${NC}"
    echo -e "   MagicDNS:    ${CYAN}${ts_dns}${NC}"
    echo -e "   DNS mode:    ${GREEN}accept-dns=false (internet safe)${NC}"
  else
    echo -e "   Status:      ${RED}Not running ✗${NC}"
  fi

  # ── Internet safety check ─────────────────────────────
  echo -e "\n${BOLD}🌐 Internet Connectivity${NC}"
  if curl -sf --max-time 5 https://1.1.1.1 -o /dev/null; then
    echo -e "   Raw IP:      ${GREEN}✓ (routing OK)${NC}"
  else
    echo -e "   Raw IP:      ${RED}✗ BROKEN${NC}"
  fi
  if nslookup google.com 8.8.8.8 &>/dev/null; then
    echo -e "   DNS:         ${GREEN}✓ (resolving OK)${NC}"
  else
    echo -e "   DNS:         ${RED}✗ BROKEN — run: ./setup.sh doctor${NC}"
  fi

  # ── Ollama ────────────────────────────────────────────
  echo -e "\n${BOLD}🧠 Ollama${NC}"
  if curl -sf "http://127.0.0.1:${OLLAMA_PORT:-11434}/api/tags" -o /dev/null; then
    echo -e "   Status:      ${GREEN}Running ✓${NC}  [127.0.0.1:${OLLAMA_PORT:-11434}]"
    echo -e "   Binding:     ${GREEN}Loopback only (LAN cannot reach directly)${NC}"
    echo -e "   Sandbox:     ${CYAN}${ENABLE_SANDBOX:-unknown}${NC}"
    if [[ "${IS_APPLE_SILICON:-false}" == "true" ]]; then
      local gpu_mb
      gpu_mb=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "N/A")
      echo -e "   Metal GPU:   ${CYAN}${gpu_mb}MB allocated${NC}"
    fi
    # List loaded models
    local models
    models=$(curl -sf "http://127.0.0.1:${OLLAMA_PORT:-11434}/api/tags" 2>/dev/null \
      | python3 -c "
import sys, json
d = json.load(sys.stdin)
for m in d.get('models', []):
    size_gb = m.get('size', 0) / 1_073_741_824
    print(f\"   Model:       {m['name']} ({size_gb:.1f} GB)\")
" 2>/dev/null || echo "   Models:      (none pulled yet)")
    echo -e "$models"
  else
    echo -e "   Status:      ${RED}Not responding ✗${NC}"
  fi

  # ── Tailscale Serve ───────────────────────────────────
  echo -e "\n${BOLD}🔗 Tailscale Serve (Ollama proxy)${NC}"
  if tailscale serve status &>/dev/null 2>&1; then
    echo -e "   Status:      ${GREEN}Active ✓${NC}"
    tailscale serve status 2>/dev/null | sed 's/^/   /'
  else
    echo -e "   Status:      ${YELLOW}Not configured${NC}"
  fi

  # ── Podman ────────────────────────────────────────────
  if command -v podman &>/dev/null && [[ -n "${PODMAN_MACHINE_NAME:-}" ]]; then
    echo -e "\n${BOLD}🐳 Podman Dev Sandbox${NC}"
    local mstate
    mstate=$("$podman_bin" machine list --format '{{.Name}} {{.Running}}' 2>/dev/null \
      | awk -v m="${PODMAN_MACHINE_NAME}" '$1==m{print $2}' || echo "unknown")
    if [[ "$mstate" == "true" ]]; then
      echo -e "   Machine:     ${GREEN}Running ✓${NC}  [${PODMAN_MACHINE_NAME}]"
      echo -e "   Security:    ${GREEN}Model files NOT mounted (sandboxed)${NC}"
      echo -e "   Ollama URL:  ${CYAN}http://host.containers.internal:${OLLAMA_PORT:-11434}${NC}"
    else
      echo -e "   Machine:     ${YELLOW}Stopped${NC}"
    fi
  fi

  # ── Security summary ──────────────────────────────────
  echo -e "\n${BOLD}🔐 Security${NC}"
  local model_perm
  model_perm=$(stat -f "%Sp" "${OLLAMA_HOME:-${HOME}/.ollama}" 2>/dev/null || echo "?")
  echo -e "   Model dir:   ${CYAN}${OLLAMA_HOME:-~/.ollama}${NC}  [${model_perm}]"
  [[ "$model_perm" == "drwx------" ]] \
    && echo -e "   Permissions: ${GREEN}Owner-only ✓${NC}" \
    || echo -e "   Permissions: ${YELLOW}Warning — not hardened (expected drwx------)${NC}"
  echo -e "   Access path: ${GREEN}Tailscale Serve only (tailnet-authenticated)${NC}"
  echo -e "\n${DIM}  Logs: ${LOG_DIR}/${NC}\n"
}

# ──────────────────────────────────────────────────────────────
# CMD: DOCTOR (diagnose + auto-repair)
# ──────────────────────────────────────────────────────────────
cmd_doctor() {
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi
  step "Running diagnostics"
  local issues=0
  local total_checks=0

  _chk() {
    local label="$1" test_cmd="$2" fix_cmd="${3:-}"
    total_checks=$((total_checks + 1))
    if eval "$test_cmd" &>/dev/null 2>&1; then
      echo -e "   ${GREEN}✓${NC} ${label}"
    else
      echo -e "   ${RED}✗${NC} ${label}"
      issues=$((issues + 1))
      
      if [[ -n "$fix_cmd" ]]; then
        local do_fix=false
        if [[ "$FORCE_MODE" == "true" ]]; then
          do_fix=true
        else
          # Always prompt for repair in doctor mode unless forced
          if ask_confirm "_DO_FIX" "    Issue found: $label. Attempt auto-repair?" "true"; then
             [[ "$_DO_FIX" == "true" ]] && do_fix=true
          fi
        fi

        if [[ "$do_fix" == "true" ]]; then
          warn "    Attempting repair..."
          if eval "$fix_cmd" 2>/dev/null; then
            ok "    Repaired."
          else
            warn "    Repair failed — manual action needed."
          fi
        fi
      fi
    fi
  }

  echo ""
  _chk "tailscaled process running"       "pgrep tailscaled"                   "sudo launchctl load -w ${PLIST_TS_DAEMON}"
  _chk "Tailscale has IP"                 "tailscale ip -4"                    ""
  _chk "Internet: raw IP (curl 1.1.1.1)"  "curl -sf --max-time 8 https://1.1.1.1 -o /dev/null"  ""
  _chk "Internet: DNS resolution"          "nslookup google.com 8.8.8.8"                          ""
  _chk "Ollama responding on loopback"     "curl -sf http://127.0.0.1:${OLLAMA_PORT:-11434}/api/tags -o /dev/null" \
                                           "launchctl load -w ${PLIST_OLLAMA}"
  _chk "Ollama NOT on 0.0.0.0 (secure)"   "! curl -sf --max-time 3 http://0.0.0.0:${OLLAMA_PORT:-11434}/api/tags -o /dev/null" \
                                           ""
  _chk "Model dir permissions (700)"       "[[ \$(stat -f '%Lp' '${OLLAMA_HOME:-${HOME}/.ollama}') == '700' ]]" \
                                           "chmod 700 '${OLLAMA_HOME:-${HOME}/.ollama}'"
  _chk "Tailscale Serve active"            "tailscale serve status"  \
                                           "tailscale serve --bg http://127.0.0.1:${OLLAMA_PORT:-11434}"
  _chk "Tailscale --accept-dns=false"      "tailscale debug prefs 2>/dev/null | grep -q 'CorpDNS.*false'" \
                                           "sudo tailscale set --accept-dns=false"
  _chk "Ollama LaunchAgent plist exists"   "[[ -f '${PLIST_OLLAMA}' ]]"  ""
  _chk "Tailscale LaunchDaemon exists"     "[[ -f '${PLIST_TS_DAEMON}' ]]"  ""
  _chk "Manifest file exists"             "[[ -f '${MANIFEST}' ]]"  ""

  if [[ "${IS_APPLE_SILICON:-false}" == "true" ]]; then
    _chk "Metal GPU daemon loaded"         "sudo launchctl list 2>/dev/null | grep -q '${DEVNET_NAME}.gpu-memory'" \
                                           "sudo launchctl load -w ${PLIST_GPU_DAEMON}"
    _chk "Metal GPU memory applied"        "sysctl -n iogpu.wired_limit_mb 2>/dev/null | grep -qv '^0$'" \
                                           "sudo sysctl iogpu.wired_limit_mb=\$(( \$(sysctl -n hw.memsize) / 1048576 * ${GPU_MEMORY_PERCENT:-80} / 100 ))"
    _chk "Flash Attention enabled"         "launchctl getenv OLLAMA_FLASH_ATTENTION 2>/dev/null | grep -q '1'" \
                                           "launchctl setenv OLLAMA_FLASH_ATTENTION 1"
  fi

  if [[ "${INSTALL_PODMAN:-true}" == "true" ]] && command -v podman &>/dev/null; then
    _chk "Podman machine running"          \
      "podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -q '^${PODMAN_MACHINE_NAME:-devbox} true'" \
      "${BREW_PREFIX}/bin/podman machine start ${PODMAN_MACHINE_NAME:-devbox}"
    _chk "Podman LaunchAgent plist exists" "[[ -f '${PLIST_PODMAN}' ]]"  ""
  fi

  if [[ "${ENABLE_SANDBOX:-true}" == "true" ]]; then
    _chk "Ollama sandbox profile exists"   "[[ -f '${SANDBOX_PROFILE}' ]]"  ""
    _chk "sandbox-exec wrapping Ollama"    "grep -q 'sandbox-exec' '${PLIST_OLLAMA}' 2>/dev/null"  ""
  fi

  echo ""
  if [[ $issues -eq 0 ]]; then
    ok "All ${total_checks} checks passed — stack is fully healthy."
  else
    warn "${issues} issue(s) detected out of ${total_checks} checks."
    echo -e "  ${DIM}Run './setup.sh logs all' for detailed logs.${NC}"
    echo -e "  ${DIM}Run './setup.sh reset' for a full clean reinstall.${NC}"
  fi
  echo ""
}

# ──────────────────────────────────────────────────────────────
# CMD: LOGS
# ──────────────────────────────────────────────────────────────
cmd_logs() {
  local svc="${1:-all}"
  local log_files=()

  case "$svc" in
    ollama)
      log_files=(
        "${LOG_DIR}/ollama.log"
        "${LOG_DIR}/ollama.error.log"
      )
      ;;
    tailscale)
      log_files=(
        "${LOG_DIR}/tailscaled.log"
      )
      ;;
    podman)
      log_files=(
        "${LOG_DIR}/podman-machine.log"
        "${LOG_DIR}/podman-launch.log"
      )
      ;;
    gpu)
      log_files=(
        "${LOG_DIR}/gpu-memory.log"
      )
      ;;
    all)
      # Collect every .log file in LOG_DIR that exists
      while IFS= read -r f; do
        log_files+=("$f")
      done < <(find "$LOG_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null | sort)
      ;;
    *)
      die "Unknown service: '${svc}'\n  Options: ollama | tailscale | podman | gpu | all"
      ;;
  esac

  # Filter to only existing files
  local existing=()
  for f in "${log_files[@]}"; do
    [[ -f "$f" ]] && existing+=("$f")
  done

  if [[ ${#existing[@]} -eq 0 ]]; then
    warn "No log files found for '${svc}' in ${LOG_DIR}/"
    info "Log files will appear once services are running."
    return
  fi

  info "Tailing ${#existing[@]} log file(s) — Ctrl+C to stop:"
  printf "  %s\n" "${existing[@]}"
  echo ""
  tail -f "${existing[@]}"
}

# ──────────────────────────────────────────────────────────────
# CMD: TEST (Self-Diagnostic Suite)
# ──────────────────────────────────────────────────────────────
cmd_test() {
  local mode="${1:-standalone}"
  
  echo -e "\n${BOLD}${CYAN}  setup.sh — Self-Test Suite${NC}"
  if [[ "$mode" == "dry-run" ]]; then
    info "Running tests in --dry-run mode (Install will proceed if clear)"
  elif [[ "$mode" == "install" ]]; then
    info "Pre-install validation tests running..."
  else
    info "Running standalone tests..."
  fi
  
  local failed=0
  local total=0

  _t() {
    local label="$1" test_cmd="$2"
    total=$((total + 1))
    if eval "$test_cmd" &>/dev/null 2>&1; then
      echo -e "   ${GREEN}✓${NC} ${label}"
    else
      echo -e "   ${RED}✗${NC} ${label}"
      failed=$((failed + 1))
    fi
  }

  echo ""
  
  # 1. Syntax Check (skip if piped via curl)
  _t "Bash syntax check (bash -n)" "[[ ! -f \"\$0\" ]] || bash -n \"\$0\""

  # 2. Core generic utilities check
  for tool in curl awk lsof nslookup launchctl; do
    _t "Base tool present: ${tool}" "command -v ${tool}"
  done

  # 3. macOS environment specific
  _t "Is macOS (Darwin)" "[[ \"\$(uname)\" == \"Darwin\" ]]"
  _t "sw_vers command present" "command -v sw_vers"
  
  # 4. CPU type / sysctl exists
  _t "sysctl tool present" "command -v sysctl"

  # 5. Sandbox functionality (conditional)
  if [[ "${ENABLE_SANDBOX:-true}" == "true" ]]; then
    _t "sandbox-exec functional" "/usr/bin/sandbox-exec -n no-network echo 'sb test' | grep 'sb test'"
  else
    info "   ${DIM}- Skipped sandbox check (ENABLE_SANDBOX=false)${NC}"
  fi

  echo ""
  if [[ $failed -eq 0 ]]; then
    ok "All ${total} tests passed."
    if [[ "$mode" == "standalone" ]]; then
      echo -e "  ${DIM}Self tests indicate script capabilities and OS requirements are intact.${NC}\n"
    fi
  else
    die "Failed ${failed}/${total} self-tests. Cannot proceed safely."
  fi
}

# ──────────────────────────────────────────────────────────────
# CMD: VERSION
# ──────────────────────────────────────────────────────────────
cmd_version() {
  if [[ -f "$CONFIG_SNAPSHOT" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SNAPSHOT" 2>/dev/null || true
  fi
  echo "setup.sh v${DEVNET_VERSION}"
  echo "  Installed:  ${INSTALL_DATE:-not installed}"
  echo "  Config:     ${CONFIG_SNAPSHOT}"
  echo "  Manifest:   ${MANIFEST}"
  echo "  Logs:       ${LOG_DIR}"
}

# ──────────────────────────────────────────────────────────────
# CMD: HELP
# ──────────────────────────────────────────────────────────────
cmd_help() {
  echo ""
  if [[ -n "$GUM_BIN" && -t 1 ]]; then
    "$GUM_BIN" style \
      --foreground 45 --border-foreground 45 --border rounded \
      --align left --width 64 --padding "0 2" \
      "setup.sh v${DEVNET_VERSION} — Help" 2>/dev/null || true
    echo ""
  else
    echo -e "${BOLD}setup.sh v${DEVNET_VERSION}${NC} — Enterprise macOS AI Stack Manager"
    echo ""
  fi

  echo -e "  ${BOLD}Commands:${NC}"
  echo -e "  install [--defaults]      Full interactive setup"
  echo -e "                            --defaults: skip prompts, use env vars + defaults"
  echo -e "  uninstall                 Remove all services (keeps model files)"
  echo -e "  uninstall --purge         Remove all + delete logs and config"
  echo -e "  reset [--defaults]        Uninstall + clean reinstall"
  echo -e "  start                     Start all stopped services"
  echo -e "  stop                      Stop Ollama + Podman (Tailscale stays)"
  echo -e "  status                    Live health dashboard"
  echo -e "  test                      Run internal self-diagnostic suite"
  echo -e "  logs [svc]                Tail logs — svc: ollama|tailscale|podman|gpu|all"
  echo -e "  doctor [--force]          Diagnose + auto-repair all issues"
  echo -e "  version                   Show version + install info"
  echo ""
  echo -e "  ${BOLD}Global Flags:${NC}"
  echo -e "  -f, --force               Force full reconfiguration (overwrite env/confirmations)"
  echo -e "  --dry-run                 Simulate changes without modifying system"
  echo -e "  ${BOLD}Required for install:${NC}"
  echo -e "  export TAILSCALE_AUTHKEY=tskey-auth-XXXX"
  echo -e "  (Get one: https://login.tailscale.com/admin/settings/keys)"
  echo -e "  Set: Reusable ✓  Pre-approved ✓"
  echo ""
  echo -e "  ${BOLD}Full env override example (non-interactive):${NC}"
  echo -e "  export TAILSCALE_AUTHKEY=tskey-auth-XXXX"
  echo -e "  export TAILSCALE_HOSTNAME=mac-ai"
  echo -e "  export OLLAMA_PORT=11434"
  echo -e "  export GPU_MEMORY_PERCENT=85"
  echo -e "  export OLLAMA_NUM_PARALLEL=6"
  echo -e "  export PODMAN_CPUS=6"
  echo -e "  export PODMAN_MEMORY_MB=12288"
  echo -e "  export ENABLE_SANDBOX=true"
  echo -e "  ./setup.sh install --defaults"
  echo ""
  echo -e "  ${BOLD}Architecture:${NC}"
  echo -e "  Ollama      → host (Metal GPU), 127.0.0.1 only, sandbox-exec hardened"
  echo -e "  Tailscale   → system daemon, --accept-dns=false (internet safe)"
  echo -e "  Tailscale   → Serve = ONLY access path from tailnet to Ollama"
  echo -e "  Podman      → isolated Linux VM, zero model file access"
  echo ""
}

# ──────────────────────────────────────────────────────────────
# MAIN DISPATCHER
# ──────────────────────────────────────────────────────────────
main() {
  # Always create log dir first so logging never fails
  mkdir -p "$LOG_DIR" 2>/dev/null || true

  # Parse global flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)  FORCE_MODE="true"; shift ;;
      --dry-run)   DRY_RUN="true"; shift ;;
      --defaults)  USE_DEFAULTS="true"; shift ;;
      -*) # Assume it's a command-specific flag or stop at command
          break ;;
      *) break ;;
    esac
  done

  # Parse command
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    install)    cmd_install   "$@" ;;
    uninstall)  ensure_gum; cmd_uninstall "$@" ;;
    reset)      cmd_reset     "$@" ;;
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    status)     cmd_status ;;
    test)       ensure_gum; cmd_test "standalone" ;;
    logs)       cmd_logs      "$@" ;;
    doctor)     ensure_gum; cmd_doctor "$@" ;;
    version)    cmd_version ;;
    help|--help|-h) ensure_gum; cmd_help ;;
    *)
      echo -e "${RED}Unknown command: '${cmd}'${NC}"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"

