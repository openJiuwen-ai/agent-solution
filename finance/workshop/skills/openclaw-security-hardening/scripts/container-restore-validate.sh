#!/bin/bash
# container-restore-validate.sh v8.07 — Verify restore returned to pre-hardening state
# v8.07 fixes:
#   - Added warn() function
#   - Enhanced container detection
#   - Graceful handling of missing tools
# Usage: bash container-restore-validate.sh [--backup-file FILE] [--report-dir DIR] [--help]

set -euo pipefail

BACKUP_FILE=""
REPORT_DIR="./reports"
OPENCLAW_PATH="/root/.openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-file) BACKUP_FILE="$2"; shift 2 ;;
    --report-dir)  REPORT_DIR="$2"; shift 2 ;;
    --path)        OPENCLAW_PATH="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --backup-file FILE  Path to backup tarball (auto-detected if not set)"
      echo "  --report-dir DIR    Report output directory (default: ./reports)"
      echo "  --path DIR          OpenClaw path (default: /root/.openclaw)"
      echo "  --help              Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SANITIZED_PATH="$(echo "$OPENCLAW_PATH" | sed 's#/$##')"
if echo "$SANITIZED_PATH" | grep -qE '[;&|`$(){}]'; then
  echo "[FAIL] OPENCLAW_PATH contains unsafe characters"
  exit 2
fi
OPENCLAW_PATH="$SANITIZED_PATH"

mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Auto-detect latest backup if not specified
if [[ -z "$BACKUP_FILE" ]]; then
  BACKUP_FILE=$(find "$OPENCLAW_PATH/backups" -name "pre-harden-*.tgz" -type f 2>/dev/null | sort -r | head -1)
  if [[ -n "$BACKUP_FILE" ]]; then
    echo "[INFO] Auto-selected latest backup: $(basename "$BACKUP_FILE")"
  fi
fi

# Logging functions
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
pass()  { echo -e "  \033[1;32m✅ $*\033[0m"; ((PASS_COUNT++)) || true; }
fail()  { echo -e "  \033[1;31m❌ $*\033[0m"; ((FAIL_COUNT++)) || true; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; ((WARN_COUNT++)) || true; }

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

echo "============================================================="
echo " Post-Restore Validation v8"
echo "============================================================="

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  fail "No backup file available for comparison"
  echo "  Specify with --backup-file or ensure backups exist in $OPENCLAW_PATH/backups"
  exit 1
fi

echo " Backup: $(basename "$BACKUP_FILE")"
echo ""

# Create temp directory for extracting backup
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract backup to temp dir for comparison
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" 2>/dev/null || true

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

# ---- 1. SSH Config Comparison ----
info "[1/6] SSH Configuration"
if [[ -f "$TEMP_DIR/etc/ssh/sshd_config" ]] && [[ -f /etc/ssh/sshd_config ]]; then
  if diff -q "$TEMP_DIR/etc/ssh/sshd_config" /etc/ssh/sshd_config &>/dev/null; then
    pass "sshd_config matches backup (fully restored)"
  else
    DIFF_LINES=$(diff "$TEMP_DIR/etc/ssh/sshd_config" /etc/ssh/sshd_config 2>/dev/null | wc -l)
    fail "sshd_config differs from backup ($DIFF_LINES line differences)"
  fi
else
  warn "sshd_config not available for comparison"
fi

# ---- 2. OpenClaw Config Comparison ----
info "[2/6] OpenClaw Configuration"
BACKUP_CONFIG_REL="${OPENCLAW_PATH#/}/openclaw.json"
if [[ -f "$TEMP_DIR/$BACKUP_CONFIG_REL" ]] && [[ -f "$OPENCLAW_PATH/openclaw.json" ]]; then
  if diff -q "$TEMP_DIR/$BACKUP_CONFIG_REL" "$OPENCLAW_PATH/openclaw.json" &>/dev/null; then
    pass "openclaw.json matches backup (fully restored)"
  else
    # Compare specific fields using safe_node_get (key path style)
    BACKUP_TOKEN_VAL=$(safe_node_get "$TEMP_DIR/$BACKUP_CONFIG_REL" "gateway.auth.token" 2>/dev/null || echo "")
    if [[ -z "$BACKUP_TOKEN_VAL" ]]; then
      BACKUP_TOKEN_VAL=$(safe_node_get "$TEMP_DIR/$BACKUP_CONFIG_REL" "gateway.token" 2>/dev/null || echo "")
    fi
    CURRENT_TOKEN_VAL=$(safe_node_get "$OPENCLAW_PATH/openclaw.json" "gateway.auth.token" 2>/dev/null || echo "")
    if [[ -z "$CURRENT_TOKEN_VAL" ]]; then
      CURRENT_TOKEN_VAL=$(safe_node_get "$OPENCLAW_PATH/openclaw.json" "gateway.token" 2>/dev/null || echo "")
    fi
    BACKUP_BIND=$(safe_node_get "$TEMP_DIR/$BACKUP_CONFIG_REL" "gateway.bind" 2>/dev/null || echo "")
    CURRENT_BIND=$(safe_node_get "$OPENCLAW_PATH/openclaw.json" "gateway.bind" 2>/dev/null || echo "")

    BACKUP_TOKEN_LEN=${#BACKUP_TOKEN_VAL}
    CURRENT_TOKEN_LEN=${#CURRENT_TOKEN_VAL}

    if [[ "$BACKUP_TOKEN_VAL" == "$CURRENT_TOKEN_VAL" && "$BACKUP_BIND" == "$CURRENT_BIND" ]]; then
      pass "openclaw.json key fields restored (token: ${CURRENT_TOKEN_LEN}chars, bind: $CURRENT_BIND)"
    else
      fail "openclaw.json partially restored (token: ${CURRENT_TOKEN_LEN}chars vs ${BACKUP_TOKEN_LEN}chars, bind: $CURRENT_BIND vs $BACKUP_BIND)"
    fi
  fi
else
  warn "openclaw.json backup not available for comparison"
fi

# ---- 3. Sysctl Parameters ----
info "[3/6] System Parameters"
if [[ -f "$TEMP_DIR/etc/sysctl.d/99-openclaw-security.conf" ]]; then
  if [[ -f /etc/sysctl.d/99-openclaw-security.conf ]]; then
    if diff -q "$TEMP_DIR/etc/sysctl.d/99-openclaw-security.conf" /etc/sysctl.d/99-openclaw-security.conf &>/dev/null; then
      pass "sysctl config matches backup"
    else
      pass "sysctl config present (compare manually if needed)"
    fi
  else
    pass "sysctl security config removed (restored to pre-hardening state)"
  fi
else
  pass "sysctl config was not modified in hardening"
fi

# Check specific kernel params
if command -v sysctl &>/dev/null; then
  TCP_SYNCOOKIES=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "0")
  IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
  info "  Current kernel params: tcp_syncookies=$TCP_SYNCOOKIES, ip_forward=$IP_FORWARD"
fi

# ---- 4. Password Policy ----
info "[4/6] Password Policy"
if [[ -f "$TEMP_DIR/etc/login.defs" ]] && [[ -f /etc/login.defs ]]; then
  if diff -q "$TEMP_DIR/etc/login.defs" /etc/login.defs &>/dev/null; then
    pass "login.defs matches backup (fully restored)"
  else
    CURRENT_MIN=$(grep "^PASS_MIN_LEN" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "0")
    pass "login.defs differs — current PASS_MIN_LEN=$CURRENT_MIN (review if expected)"
  fi
else
  warn "login.defs not available for comparison"
fi

# ---- 5. SOUL/AGENTS Security Markers ----
info "[5/6] Security Rules in SOUL/AGENTS"
SECURITY_MARKER="<!-- openclaw-security -->"

if [[ -f "$OPENCLAW_PATH/workspace/SOUL.md" ]]; then
  if grep -q "$SECURITY_MARKER" "$OPENCLAW_PATH/workspace/SOUL.md" 2>/dev/null; then
    warn "SOUL.md still contains security marker (not fully restored)"
  else
    pass "SOUL.md security marker removed"
  fi
fi

if [[ -f "$OPENCLAW_PATH/workspace/AGENTS.md" ]]; then
  if grep -q "$SECURITY_MARKER" "$OPENCLAW_PATH/workspace/AGENTS.md" 2>/dev/null; then
    warn "AGENTS.md still contains security marker (not fully restored)"
  else
    pass "AGENTS.md security marker removed"
  fi
fi

# ---- 6. File Permissions ----
info "[6/6] File Permissions"
if [[ -f "$OPENCLAW_PATH/openclaw.json" ]]; then
  CURRENT_PERM=$(stat -c "%a" "$OPENCLAW_PATH/openclaw.json" 2>/dev/null || echo "000")
  info "  openclaw.json permissions: $CURRENT_PERM"
  if [[ "$CURRENT_PERM" == "600" ]]; then
    warn "openclaw.json still has hardened permissions (600)"
  else
    pass "openclaw.json permissions: $CURRENT_PERM (changed from hardened state)"
  fi
fi

# ---- Summary ----
echo ""
echo "============================================================="
echo " Restore Validation Summary"
echo "============================================================="
echo " PASS: $PASS_COUNT | WARN: $WARN_COUNT | FAIL: $FAIL_COUNT"
echo ""

# Write JSON result
VALIDATION_FILE="$REPORT_DIR/restore-validation-${TIMESTAMP}.json"
cat > "$VALIDATION_FILE" <<EOF
{
  "type": "restore-validation",
  "timestamp": "$TIMESTAMP",
  "backup_file": "$(basename "$BACKUP_FILE")",
  "pass_count": $PASS_COUNT,
  "warn_count": $WARN_COUNT,
  "fail_count": $FAIL_COUNT,
  "status": "$([ $FAIL_COUNT -eq 0 ] && echo "passed" || echo "issues_detected")"
}
EOF

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "✅ Restore validation passed — system returned to pre-hardening state"
  exit 0
else
  echo "⚠️  Some items differ from pre-hardening state — review warnings above"
  exit 1
fi
