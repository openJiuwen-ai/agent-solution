#!/bin/bash
# container-rocky-audit.sh v8.07 — Pre-audit for OpenClaw
# v8.07 fixes:
#   - Added warn() function
#   - Multi-distro support
#   - Enhanced container detection
# Usage: bash container-rocky-audit.sh [--output DIR] [--level N] [--path DIR] [--help]

set -euo pipefail

# Defaults
OUTPUT_DIR="./reports"
LEVEL=3
OPENCLAW_PATH="/root/.openclaw"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)   OUTPUT_DIR="$2"; shift 2 ;;
    --level)    LEVEL="$2"; shift 2 ;;
    --path)     OPENCLAW_PATH="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --output DIR   Report output directory (default: ./reports)"
      echo "  --level N      Target security level 1-5 (default: 3)"
      echo "  --path PATH    OpenClaw install path (default: /root/.openclaw)"
      echo "  --help         Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Sanitize OPENCLAW_PATH
SANITIZED_PATH="$(echo "$OPENCLAW_PATH" | sed 's#/$##')"
if echo "$SANITIZED_PATH" | grep -qE '[;&|`$(){}]'; then
  echo "[FAIL] OPENCLAW_PATH contains unsafe characters: $OPENCLAW_PATH"
  exit 2
fi
OPENCLAW_PATH="$SANITIZED_PATH"

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

# Detect distro
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}
DISTRO=$(detect_distro)

# Timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUTPUT_DIR"

REPORT_MD="$OUTPUT_DIR/pre-assessment-${TIMESTAMP}.md"
REPORT_JSON="$OUTPUT_DIR/pre-assessment-${TIMESTAMP}.json"

# Logging functions
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
fail()  { echo -e "\033[1;31m[FAIL]\033[0m $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
pass()  { echo -e "\033[1;32m[PASS]\033[0m $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

echo "============================================================="
echo " OpenClaw Pre-Assessment v8 — $CONTAINER_MODE mode"
echo "============================================================="
echo ""

# ---- 1. System Info ----
info "[1/7] System Information"
ROCKY_VERSION="unknown"
KERNEL_VER="unknown"
HAS_DOCKER=false
HAS_PODMAN=false
CONTAINER_ENGINE=""

pass "OS: $DISTRO ($(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown'))"

KERNEL_VER=$(uname -r)
pass "Kernel: $KERNEL_VER"

if command -v docker &>/dev/null; then
  HAS_DOCKER=true
  CONTAINER_ENGINE="docker"
  pass "Docker: $(docker --version 2>/dev/null | cut -d',' -f1 || echo 'installed')"
fi

if command -v podman &>/dev/null; then
  HAS_PODMAN=true
  CONTAINER_ENGINE="podman"
  pass "Podman: $(podman --version 2>/dev/null | awk '{print $3}' || echo 'installed')"
fi

# ---- 2. OpenClaw Installation ----
info "[2/7] OpenClaw Installation"
OPENCLAW_CONFIG="$OPENCLAW_PATH/openclaw.json"

if [[ -d "$OPENCLAW_PATH" ]]; then
  pass "OpenClaw directory exists: $OPENCLAW_PATH"
else
  fail "OpenClaw directory not found: $OPENCLAW_PATH"
  echo "[ERROR] Cannot continue without OpenClaw installation" > "$REPORT_MD"
  exit 1
fi

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

if [[ -f "$OPENCLAW_CONFIG" ]]; then
  pass "openclaw.json exists"

  # Token length check
  TOKEN_VAL=$(safe_node_get "$OPENCLAW_CONFIG" "gateway.auth.token" 2>/dev/null || echo "")
  TOKEN_LEN=${#TOKEN_VAL}

  if [[ "$TOKEN_LEN" -ge 32 ]]; then
    pass "Gateway token length OK: $TOKEN_LEN chars"
  else
    fail "Gateway token too short: $TOKEN_LEN (need ≥32)"
  fi

  # Bind address
  BIND=$(safe_node_get "$OPENCLAW_CONFIG" "gateway.bind" 2>/dev/null || echo "")

  if [[ "$BIND" == "127.0.0.1" || "$BIND" == "localhost" || "$BIND" == "loopback" ]]; then
    pass "Gateway bind: $BIND (localhost OK)"
  elif [[ -z "$BIND" ]]; then
    warn "Gateway bind not set (may bind to 0.0.0.0)"
  else
    fail "Gateway bound to: $BIND (not localhost — security risk)"
  fi
else
  fail "openclaw.json not found at $OPENCLAW_CONFIG"
fi

# ---- 3. File Permissions ----
info "[3/7] File Permissions"
if [[ -f "$OPENCLAW_CONFIG" ]]; then
  PERM=$(stat -c "%a" "$OPENCLAW_CONFIG" 2>/dev/null || echo "000")
  if [[ "$PERM" == "600" ]]; then
    pass "openclaw.json permissions: 600"
  else
    fail "openclaw.json permissions: $PERM (should be 600)"
  fi
fi

DIR_PERM=$(stat -c "%a" "$OPENCLAW_PATH" 2>/dev/null || echo "000")
if [[ "${DIR_PERM:0:1}" == "7" ]]; then
  pass "OpenClaw directory permissions OK: $DIR_PERM"
else
  fail "OpenClaw directory permissions too open: $DIR_PERM"
fi

if [[ -f "$OPENCLAW_PATH/.env" ]]; then
  ENV_PERM=$(stat -c "%a" "$OPENCLAW_PATH/.env" 2>/dev/null || echo "000")
  if [[ "$ENV_PERM" == "600" ]]; then
    pass ".env permissions: 600"
  else
    fail ".env permissions: $ENV_PERM (should be 600)"
  fi
else
  warn "No .env file (consider using one for secrets)"
fi

# ---- 4. Sensitive Data Scan ----
info "[4/7] Sensitive Data Scan"
CRED_COUNT=0
if find "$OPENCLAW_PATH" -maxdepth 2 -name "*.json" -type f 2>/dev/null | grep -v node_modules | xargs grep -lE '(api[_-]?key|secret|password)' 2>/dev/null | grep -v '"cost"' | grep -v 'YOUR_' | grep -v 'example' | grep -q .; then
  fail "Possible plaintext credentials found in JSON configs"
  CRED_COUNT=1
else
  pass "No plaintext credentials in JSON configs"
fi

# ---- 5. System Security Baseline ----
info "[5/7] System Security Baseline ($CONTAINER_MODE mode)"

if [[ "$CONTAINER_MODE" == "host" ]]; then
  # SSH check
  if [[ -f /etc/ssh/sshd_config ]]; then
    ROOT_LOGIN=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "")
    if [[ "$ROOT_LOGIN" == "no" || "$ROOT_LOGIN" == "prohibit-password" ]]; then
      pass "SSH PermitRootLogin: $ROOT_LOGIN"
    else
      warn "SSH PermitRootLogin: ${ROOT_LOGIN:-(not set)}"
    fi
  else
    warn "sshd_config not found"
  fi

  # firewalld
  if command -v systemctl &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    pass "firewalld is running"
  else
    warn "firewalld is not running"
  fi

  # SELinux
  if command -v getenforce &>/dev/null; then
    SELINUX_STATE=$(getenforce 2>/dev/null || echo "Unknown")
    if [[ "$SELINUX_STATE" == "Enforcing" ]]; then
      pass "SELinux: Enforcing"
    else
      warn "SELinux: $SELINUX_STATE"
    fi
  fi
else
  info "  (Container mode: skipping host-level SSH/firewall/SELinux checks)"
  pass "Container mode detected — host-level checks skipped"
fi

# ---- 6. Container Security ----
info "[6/7] Container Security"
if $HAS_DOCKER; then
  CONTAINER_ID=$(docker ps --filter "name=openclaw" --format "{{.ID}}" 2>/dev/null | head -1)
  if [[ -n "$CONTAINER_ID" ]]; then
    pass "OpenClaw container running (docker): ${CONTAINER_ID:0:12}"
  else
    warn "No OpenClaw container found (docker)"
  fi
fi

if $HAS_PODMAN; then
  CONTAINER_ID=$(podman ps --filter "name=openclaw" --format "{{.ID}}" 2>/dev/null | head -1)
  if [[ -n "$CONTAINER_ID" ]]; then
    pass "OpenClaw container running (podman): ${CONTAINER_ID:0:12}"
  fi
fi

# ---- 7. Risk Score ----
info "[7/7] Risk Score Calculation"
SCORE=$((FAIL_COUNT * 5 + WARN_COUNT * 2))
if [[ $SCORE -gt 100 ]]; then SCORE=100; fi

echo ""
echo "============================================================="
echo " Pre-Assessment Complete"
echo "============================================================="
echo " PASS: $PASS_COUNT | WARN: $WARN_COUNT | FAIL: $FAIL_COUNT"
echo " Risk Score: $SCORE/100 (lower = better)"
echo ""

if [[ $SCORE -lt 15 ]]; then
  echo "✅ Security status: GOOD"
elif [[ $SCORE -lt 30 ]]; then
  echo "⚠️  Security status: MEDIUM — hardening recommended"
else
  echo "🔴 Security status: HIGH — hardening required"
fi

echo ""
echo "📄 Reports:"
echo "   Markdown: $REPORT_MD"
echo "   JSON:     $REPORT_JSON"

# ---- Write Markdown Report ----
cat > "$REPORT_MD" <<EOF
# OpenClaw Pre-Assessment Report

**Date:** $(date)
**Mode:** $CONTAINER_MODE
**Distro:** $DISTRO
**Level:** L$LEVEL
**OpenClaw Path:** $OPENCLAW_PATH

## Results

| Category | PASS | WARN | FAIL |
|----------|------|------|------|
| Overall | $PASS_COUNT | $WARN_COUNT | $FAIL_COUNT |

**Risk Score: $SCORE/100**

## System Info
- OS: $DISTRO
- Kernel: $KERNEL_VER
- Container Engine: ${CONTAINER_ENGINE:-none}
- Container Mode: $CONTAINER_MODE

## Findings
(Token length: $TOKEN_LEN, Bind: ${BIND:-not set}, Config perm: ${PERM:-n/a})

---
*Generated by openclaw-security-container-rocky-v8.07*
EOF

# ---- Write JSON Report (structured) ----
cat > "$REPORT_JSON" <<EOF
{
  "version": "8.0",
  "type": "pre-assessment",
  "timestamp": "$TIMESTAMP",
  "container_mode": "$CONTAINER_MODE",
  "distro": "$DISTRO",
  "kernel": "$KERNEL_VER",
  "container_engine": "${CONTAINER_ENGINE:-none}",
  "openclaw_path": "$OPENCLAW_PATH",
  "target_level": "L$LEVEL",
  "token_length": $TOKEN_LEN,
  "bind_address": "${BIND:-N/A}",
  "config_permissions": "${PERM:-N/A}",
  "dir_permissions": "${DIR_PERM:-N/A}",
  "credentials_found": $CRED_COUNT,
  "pass_count": $PASS_COUNT,
  "warn_count": $WARN_COUNT,
  "fail_count": $FAIL_COUNT,
  "risk_score": $SCORE
}
EOF
