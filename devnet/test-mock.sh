#!/usr/bin/env bash
# ============================================================
#  test-mock.sh — Enterprise Mock Test Suite for setup.sh
#  Runs the full install/doctor/status/stop/start pipeline
#  inside a macOS-mock Podman container.
#
#  Usage:
#    ./test-mock.sh              # interactive (requires .env)
#    TAILSCALE_AUTHKEY=tskey-auth-MOCK ./test-mock.sh  # CI
#    ./test-mock.sh --no-rebuild # skip image rebuild
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass() { echo -e "   ${GREEN}✓${NC} $*"; }
fail() { echo -e "   ${RED}✗${NC} $*"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "   ${CYAN}→${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}━━ $* ${NC}"; }

FAILURES=0
REBUILD=true
[[ "${1:-}" == "--no-rebuild" ]] && REBUILD=false

# ────────────────────────────────────────────────────────────
# 1. STATIC ANALYSIS (runs on host, no container needed)
# ────────────────────────────────────────────────────────────
section "Static Analysis"

# 1a. Bash syntax check
if bash -n setup.sh 2>/dev/null; then
  pass "Bash syntax check (bash -n)"
else
  fail "Bash syntax check FAILED"
fi

# 1b. shellcheck (if installed)
if command -v shellcheck &>/dev/null; then
  if shellcheck -S warning -e SC1090,SC1091,SC2034,SC2154 setup.sh 2>/dev/null; then
    pass "shellcheck (no warnings)"
  else
    # Collect the output and report — don't hard-fail on warnings
    ISSUES=$(shellcheck -S warning -e SC1090,SC1091,SC2034,SC2154 setup.sh 2>&1 | wc -l)
    fail "shellcheck: ${ISSUES} issue(s) found — review before shipping"
    shellcheck -S warning -e SC1090,SC1091,SC2034,SC2154 setup.sh 2>&1 | head -20 || true
  fi
else
  info "shellcheck not installed (apt install shellcheck / brew install shellcheck to enable)"
fi

# 1c. Validate all plist XML blocks baked into setup.sh
#     Strategy: extract heredoc lines between PLIST markers and validate
section "Plist XML Validation"
PLIST_ERRORS=0
while IFS= read -r tmpfile; do
  if xmllint --noout "$tmpfile" 2>/dev/null; then
    pass "Valid XML: $(basename "$tmpfile")"
  else
    fail "Invalid XML: $(basename "$tmpfile")"
    xmllint --noout "$tmpfile" 2>&1 | head -5 || true
    PLIST_ERRORS=$((PLIST_ERRORS + 1))
  fi
  rm -f "$tmpfile"
done < <(
  # Extract each plist heredoc from setup.sh into a temp file for validation
  awk '
    /^file_(write|tee) .*PLIST$/ { in_plist=1; fname=FILENAME"-plist-"NR".xml"; next }
    in_plist && /^<\?xml/ { print > fname; next }
    in_plist && /^PLIST$/ { in_plist=0; print fname; next }
    in_plist { print > fname }
  ' setup.sh 2>/dev/null
  # Also try the heredoc-final-line approach
  python3 - <<'PYEOF' 2>/dev/null || true
import re, tempfile, os, sys
content = open("setup.sh").read()
plists = re.findall(r'<<PLIST\n(.*?)\nPLIST', content, re.DOTALL)
for i, p in enumerate(plists):
    # Substitute shell vars with placeholder values
    p = re.sub(r'\$\{[^}]+\}', '/placeholder/path', p)
    p = re.sub(r'\$[A-Z_]+', 'placeholder', p)
    if '<?xml' in p:
        f = tempfile.NamedTemporaryFile(mode='w', suffix=f'-plist-{i}.xml',
                                        delete=False, prefix='/tmp/mock-test-')
        f.write(p)
        f.close()
        print(f.name)
PYEOF
)

if [[ $PLIST_ERRORS -gt 0 ]]; then
  echo -e "\n${RED}  ✗ Plist XML validation FAILED — fix before running on Mac!${NC}"
fi

# ────────────────────────────────────────────────────────────
# 2. BUILD MOCK CONTAINER
# ────────────────────────────────────────────────────────────
section "Mock Container Build"

if ! command -v podman &>/dev/null; then
  echo -e "${YELLOW}  podman not found — skipping container tests${NC}"
  echo -e "\n${YELLOW}  Static analysis result: $((FAILURES + PLIST_ERRORS)) issue(s)${NC}"
  exit $((FAILURES + PLIST_ERRORS > 0 ? 1 : 0))
fi

if [[ "$REBUILD" == "true" ]]; then
  info "Building mock-macos image..."
  if podman build -t mock-macos -f mock-macos.Dockerfile . 2>&1 | tail -3; then
    pass "Image built successfully"
  else
    fail "Image build FAILED"
    exit 1
  fi
else
  info "Skipping image rebuild (--no-rebuild)"
fi

# ────────────────────────────────────────────────────────────
# 3. RESOLVE TAILSCALE AUTH KEY
# ────────────────────────────────────────────────────────────
section "Auth Key Resolution"

TS_KEY="${TAILSCALE_AUTHKEY:-}"

# Try loading from .env file
if [[ -z "$TS_KEY" && -f ".env" ]]; then
  TS_KEY=$(grep -E '^TAILSCALE_AUTHKEY=' .env | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]')
fi

# Fall back to a safe mock key (will fail tailscale up, but mocks accept anything)
if [[ -z "$TS_KEY" ]]; then
  TS_KEY="tskey-auth-MOCK1234567890"
  info "No auth key found — using mock key (Tailscale up will be a no-op in mock)"
else
  info "Auth key loaded (${#TS_KEY} chars)"
fi

# ────────────────────────────────────────────────────────────
# 4. IN-CONTAINER TEST PIPELINE
# ────────────────────────────────────────────────────────────
section "Container Test Pipeline"

CONTAINER_SCRIPT='
set -euo pipefail
GREEN='"'"'\033[0;32m'"'"'; RED='"'"'\033[0;31m'"'"'; NC='"'"'\033[0m'"'"'
pass() { echo -e "   ${GREEN}✓${NC} $*"; }
fail() { echo -e "   ${RED}✗${NC} $*"; exit 1; }

cp /host/setup.sh /tmp/setup.sh
chmod +x /tmp/setup.sh
cd /tmp

echo -e "\n━━ install --force --defaults"
./setup.sh --force --defaults install || fail "install failed"
pass "install --force --defaults"

echo -e "\n━━ test (self-test suite)"
./setup.sh test || fail "self-test failed"
pass "test suite"

echo -e "\n━━ version"
VER=$(./setup.sh version | head -1)
echo "   Version: $VER"
[[ "$VER" == *"1.2.0"* ]] || fail "expected v1.2.0, got: $VER"
pass "version = 1.2.0"

echo -e "\n━━ doctor (non-interactive — should only REPORT, not auto-repair)"
# Redirect stdin from /dev/null to simulate non-TTY stdin
./setup.sh doctor < /dev/null
pass "doctor (non-interactive, no stdin)"

echo -e "\n━━ doctor --force (auto-repair mode)"
./setup.sh --force doctor
pass "doctor --force"

echo -e "\n━━ status"
./setup.sh status
pass "status"

echo -e "\n━━ stop"
./setup.sh stop
pass "stop"

echo -e "\n━━ start"
./setup.sh start
pass "start"

echo -e "\n━━ Plist file integrity check"
for plist_file in \
  "${HOME}/Library/LaunchAgents/com.devnet.ollama.plist" \
  "${HOME}/Library/LaunchAgents/com.devnet.podman-machine.plist"; do
  if [[ -f "$plist_file" ]]; then
    if xmllint --noout "$plist_file" 2>/dev/null; then
      pass "Valid plist: $(basename $plist_file)"
    else
      fail "INVALID plist XML: $plist_file"
    fi
  fi
done

echo ""
echo -e "   \033[0;32mAll container tests passed.\033[0m"
'

info "Running full pipeline in mock container..."
if podman run --rm \
  -e TAILSCALE_AUTHKEY="$TS_KEY" \
  -v "${SCRIPT_DIR}:/host:ro" \
  mock-macos \
  bash -c "$CONTAINER_SCRIPT" 2>&1; then
  pass "Container pipeline: all commands exit 0"
else
  fail "Container pipeline: one or more commands FAILED (see above)"
fi

# ────────────────────────────────────────────────────────────
# 5. NON-INTERACTIVE PIPE SIMULATION (no TTY stdin/stdout)
# ────────────────────────────────────────────────────────────
section "Non-Interactive Pipe Simulation (curl|bash style)"

PIPE_SCRIPT='
set -euo pipefail
cp /host/setup.sh /tmp/setup.sh && chmod +x /tmp/setup.sh && cd /tmp
# Simulate curl|bash: stdin is /dev/null, stdout is a pipe
export TAILSCALE_AUTHKEY="tskey-auth-MOCK1234567890"
./setup.sh --force --defaults install < /dev/null
./setup.sh doctor < /dev/null
echo "PIPE_TEST: exit 0"
'

if podman run --rm \
  -e TAILSCALE_AUTHKEY="$TS_KEY" \
  -v "${SCRIPT_DIR}:/host:ro" \
  mock-macos \
  bash -c "$PIPE_SCRIPT" 2>&1 | grep -q "PIPE_TEST: exit 0"; then
  pass "Non-interactive pipe simulation: no blocking reads"
else
  fail "Non-interactive pipe simulation: FAILED (may have blocked on read)"
fi

# ────────────────────────────────────────────────────────────
# 6. FINAL REPORT
# ────────────────────────────────────────────────────────────
section "Test Summary"
TOTAL_FAILURES=$((FAILURES + PLIST_ERRORS))
if [[ $TOTAL_FAILURES -eq 0 ]]; then
  echo -e "\n${GREEN}${BOLD}  ✅  All tests passed — safe to push.${NC}\n"
  exit 0
else
  echo -e "\n${RED}${BOLD}  ✗  ${TOTAL_FAILURES} test(s) FAILED — fix before pushing!${NC}\n"
  exit 1
fi
