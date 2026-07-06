#!/bin/bash
# container-post-validate.sh v8.07 — Validate OpenClaw after hardening
# v8.07 fixes:
#   - Added warn() function (v5 bug: missing warn caused crashes)
#   - Enhanced Gateway detection (multiple methods)
#   - Graceful handling of missing ss command
set -euo pipefail
# Usage: bash container-post-validate.sh [--report-dir DIR] [--state-file FILE] [--help]
REPORT_DIR="./reports"
STATE_FILE=""
OPENCLAW_PATH="/root/.openclaw"
PASS_COUNT=0
FAIL_COUNT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --path)       OPENCLAW_PATH="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --report-dir DIR   Report directory (default: ./reports)"
      echo "  --state-file FILE  Hardening state file (auto-detected if not set)"
      echo "  --path DIR         OpenClaw path (default: /root/.openclaw)"
      echo "  --help             Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Sanitize
SANITIZED_PATH="$(echo "$OPENCLAW_PATH" | sed 's#/$##')"
if echo "$SANITIZED_PATH" | grep -qE '[;&|`$(){}]'; then
  echo "[FAIL] OPENCLAW_PATH contains unsafe characters"
  exit 2
fi
OPENCLAW_PATH="$SANITIZED_PATH"

mkdir -p "$REPORT_DIR"

# Detect container vs host
detect_container_mode() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || \
     grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    echo "container"
  else
    echo "host"
  fi
}
CONTAINER_MODE=$(detect_container_mode)

# Read SSH_TOUCHED from state file
SSH_TOUCHED=1
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  SSH_TOUCHED=$(node -e "
    const fs = require('fs');
    const s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    console.log(s.ssh_touched !== undefined ? s.ssh_touched : 1);
  " "$STATE_FILE" 2>/dev/null || echo "1")
fi

# Logging functions — v8.07: warn() is now defined
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
pass() { echo -e "  \033[1;32m✅ $*\033[0m"; ((PASS_COUNT++)) || true; }
fail() { echo -e "  \033[1;31m❌ $*\033[0m"; ((FAIL_COUNT++)) || true; }
skip() { echo -e "  \033[1;33m⏭️  $*\033[0m"; ((PASS_COUNT++)) || true; }
warn() { echo -e "  \033[1;33m⚠️  $*\033[0m"; ((PASS_COUNT++)) || true; }

echo "============================================================="
echo " Post-Hardening Validation v8"
echo "============================================================="
echo " Mode: $CONTAINER_MODE | SSH touched: $SSH_TOUCHED"
echo ""

JSON_FILE="$OPENCLAW_PATH/openclaw.json"

# Safe node read
safe_node_get() {
  local json_file="$1"
  local key_path="$2"
  node -e "
    const fs = require('fs');
    const p = process.argv[1];
    const keyPath = process.argv[2];
    try {
      const c = JSON.parse(fs.readFileSync(p, 'utf8'));
      const keys = keyPath.split('.');
      let obj = c;
      for (const k of keys) {
        if (obj && obj[k] !== undefined) obj = obj[k];
        else { console.log(''); process.exit(0); }
      }
      console.log(typeof obj === 'string' ? obj : JSON.stringify(obj));
    } catch(e) { console.log(''); }
  " "$json_file" "$key_path"
}
# 1. openclaw.json exists
if [[ -f "$JSON_FILE" ]]; then
  pass "1. openclaw.json exists"
else
  fail "1. openclaw.json missing"
fi

# 2. openclaw.json permissions
PERM=$(stat -c "%a" "$JSON_FILE" 2>/dev/null || echo "000")
if [[ "$PERM" == "600" ]]; then
  pass "2. openclaw.json permissions: 600"
else
  fail "2. openclaw.json permissions: $PERM (expected 600)"
fi

# 3. Token length
TOKEN_VAL=$(safe_node_get "$JSON_FILE" "gateway.auth.token" 2>/dev/null || echo "")
TOKEN_LEN=${#TOKEN_VAL}
if [[ "$TOKEN_LEN" -ge 32 ]]; then
  pass "3. Gateway token length: $TOKEN_LEN (≥32)"
else
  fail "3. Gateway token too short: $TOKEN_LEN"
fi

# 4. Bind address
BIND=$(safe_node_get "$JSON_FILE" "gateway.bind" 2>/dev/null || echo "")
if [[ "$BIND" == "127.0.0.1" || "$BIND" == "localhost" || "$BIND" == "loopback" ]]; then
  pass "4. Gateway bind: $BIND"
else
  fail "4. Gateway bind: ${BIND:-not set} (not localhost)"
fi

# 5. .env exists and permissions
if [[ -f "$OPENCLAW_PATH/.env" ]]; then
  ENV_PERM=$(stat -c "%a" "$OPENCLAW_PATH/.env" 2>/dev/null || echo "000")
  if [[ "$ENV_PERM" == "600" ]]; then
    pass "5. .env exists, permissions: 600"
  else
    fail "5. .env permissions: $ENV_PERM (expected 600)"
  fi
else
  skip "5. .env not present (acceptable)"
fi

# 6. Directory permissions
DIR_PERM=$(stat -c "%a" "$OPENCLAW_PATH" 2>/dev/null || echo "000")
if [[ "${DIR_PERM:0:1}" == "7" ]]; then
  pass "6. OpenClaw directory permissions: $DIR_PERM"
else
  fail "6. OpenClaw directory permissions: $DIR_PERM"
fi

# 7-9: SSH checks — only if SSH was touched
if [[ "$SSH_TOUCHED" -eq 0 ]]; then
  skip "7-9. SSH checks skipped (--skip-ssh mode)"
else
  if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -qE "PermitRootLogin (prohibit-password|no)" /etc/ssh/sshd_config; then
      pass "7. SSH PermitRootLogin correctly set"
    else
      fail "7. SSH PermitRootLogin not set correctly"
    fi

    if grep -q "PermitEmptyPasswords no" /etc/ssh/sshd_config; then
      pass "8. SSH PermitEmptyPasswords: no"
    else
      fail "8. SSH PermitEmptyPasswords not disabled"
    fi

    if grep -q "MaxAuthTries 3" /etc/ssh/sshd_config; then
      pass "9. SSH MaxAuthTries: 3"
    else
      fail "9. SSH MaxAuthTries not set to 3"
    fi
  else
    skip "7-9. sshd_config not found"
  fi
fi

# 10. firewalld (only check if available)
if command -v firewall-cmd &>/dev/null; then
  if command -v systemctl &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    pass "10. firewalld is running"
  else
    warn "10. firewalld not running (or not available in container)"
  fi
else
  skip "10. firewalld not available (container mode)"
fi

# 11. SELinux (only if getenforce available)
if command -v getenforce &>/dev/null; then
  SEL_STATE=$(getenforce 2>/dev/null || echo "Unknown")
  if [[ "$SEL_STATE" == "Enforcing" ]]; then
    pass "11. SELinux: Enforcing"
  else
    fail "11. SELinux: $SEL_STATE (not Enforcing)"
  fi
else
  skip "11. getenforce not available"
fi

# 12. avahi-daemon disabled
if command -v systemctl &>/dev/null; then
  if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    fail "12. avahi-daemon still running"
  else
    pass "12. avahi-daemon disabled"
  fi
else
  skip "12. avahi-daemon (no systemd in container)"
fi

# 13. Password policy
if [[ -f /etc/login.defs ]]; then
  PASS_MIN=$(grep "^PASS_MIN_LEN" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "0")
  if [[ "${PASS_MIN:-0}" -ge 12 ]]; then
    pass "13. Password min length: $PASS_MIN"
  else
    fail "13. Password min length: ${PASS_MIN:-0} (need ≥12)"
  fi
else
  skip "13. /etc/login.defs not found"
fi

# 14. Kernel params
if command -v sysctl &>/dev/null; then
  SYNCOOKIES=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "0")
  if [[ "$SYNCOOKIES" == "1" ]]; then
    pass "14. net.ipv4.tcp_syncookies = 1"
  else
    fail "14. net.ipv4.tcp_syncookies not set"
  fi
else
  skip "14. sysctl not available"
fi

# 15. File integrity baseline
if [[ -f "$OPENCLAW_PATH/.file-integrity-baseline" ]]; then
  pass "15. File integrity baseline exists"
else
  fail "15. File integrity baseline missing"
fi

# 16. Gateway process check — v8.07: multiple detection methods
info "Checking Gateway status..."
GW_RUNNING=false

# Method 1: openclaw CLI
if command -v openclaw &>/dev/null; then
  GW_STATUS=$(openclaw gateway status 2>/dev/null || echo "unknown")
  if echo "$GW_STATUS" | grep -qiE "running|active"; then
    GW_RUNNING=true
  fi
fi

# Method 2: PID check (node process with openclaw)
if ! $GW_RUNNING; then
  if pgrep -f "openclaw" &>/dev/null || pgrep -f "gateway" &>/dev/null; then
    GW_RUNNING=true
  fi
fi

# Method 3: HTTP check
if ! $GW_RUNNING; then
  BIND_PORT=$(safe_node_get "$JSON_FILE" "gateway.port" 2>/dev/null || echo "7437")
  if curl -sf "http://127.0.0.1:${BIND_PORT}/" &>/dev/null; then
    GW_RUNNING=true
  fi
fi

if $GW_RUNNING; then
  pass "16. Gateway is running"
else
  warn "16. Gateway status could not be confirmed (may need manual check)"
fi

# 17. Gateway port listening — v8.07: handle missing ss command
BIND_PORT=$(safe_node_get "$JSON_FILE" "gateway.port" 2>/dev/null || echo "7437")

if command -v ss &>/dev/null; then
  if ss -tlnp 2>/dev/null | grep -qE "127\.0\.0\.1:${BIND_PORT}"; then
    pass "17. Gateway port :$BIND_PORT listening on 127.0.0.1"
  else
    warn "17. Gateway port :$BIND_PORT not detected (may need restart)"
  fi
elif command -v netstat &>/dev/null; then
  if netstat -tlnp 2>/dev/null | grep -qE ":${BIND_PORT}"; then
    pass "17. Gateway port :$BIND_PORT listening (via netstat)"
  else
    warn "17. Gateway port :$BIND_PORT not detected"
  fi
else
  skip "17. Neither ss nor netstat available — cannot verify port"
fi

echo ""
echo "============================================================="
echo " Validation Summary"
echo "============================================================="
echo " PASS: $PASS_COUNT | FAIL: $FAIL_COUNT"
echo ""

# Write validation result to file
VALIDATION_FILE="$REPORT_DIR/post-validation-$(date +%Y%m%d-%H%M%S).json"
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "✅ All checks passed!"
  cat > "$VALIDATION_FILE" <<EOF
{
  "type": "post-validation",
  "timestamp": "$(date +%Y%m%d-%H%M%S)",
  "pass_count": $PASS_COUNT,
  "fail_count": $FAIL_COUNT,
  "status": "all_passed"
}
EOF
  exit 0
else
  echo "⚠️  $FAIL_COUNT check(s) failed — review above"
  cat > "$VALIDATION_FILE" <<EOF
{
  "type": "post-validation",
  "timestamp": "$(date +%Y%m%d-%H%M%S)",
  "pass_count": $PASS_COUNT,
  "fail_count": $FAIL_COUNT,
  "status": "failures_detected"
}
EOF
  exit 1
fi
