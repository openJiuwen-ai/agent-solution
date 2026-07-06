#!/bin/bash
# file-perms.sh v8.07 — Fix file permissions for OpenClaw
# v8.07 fixes:
#   - Added warn() function
#   - Added --path argument
#   - Added --mode check|fix
#   - Added logging output
# Usage: bash file-perms.sh [--mode check|fix] [--path DIR] [--log FILE]

set -euo pipefail

MODE="fix"
OPENCLAW_PATH="/root/.openclaw"
LOG=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --path) OPENCLAW_PATH="$2"; shift 2 ;;
    --log)  LOG="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--mode check|fix] [--path DIR] [--log FILE]"
      echo "  --mode check    Only check permissions, don't fix"
      echo "  --mode fix      Check and fix permissions (default)"
      echo "  --path DIR      OpenClaw install path (default: /root/.openclaw)"
      echo "  --log FILE      Log file (default: stdout)"
      echo "  --help          Show this help"
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

if [[ -z "$LOG" ]]; then
  LOG="/tmp/openclaw-perms-$(date +%Y%m%d-%H%M%S).log"
fi

# Logging functions
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; echo "[INFO] $*" >> "$LOG"; }
pass()  { echo -e "\033[1;32m[PASS]\033[0m $*"; echo "[PASS] $*" >> "$LOG"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; echo "[WARN] $*" >> "$LOG"; }
fail()  { echo -e "\033[1;31m[FAIL]\033[0m $*"; echo "[FAIL] $*" >> "$LOG"; }

> "$LOG"  # Initialize log

echo "============================================================="
echo " OpenClaw File Permissions v8 — Mode: $MODE"
echo "============================================================="
echo ""

ISSUES=0
FIXED=0

# Check directories
info "Checking directory permissions..."
while IFS= read -r dir; do
  PERM=$(stat -c "%a" "$dir" 2>/dev/null || echo "000")
  if [[ "$PERM" != "700" ]]; then
    if [[ "$MODE" == "fix" ]]; then
      chmod 700 "$dir"
      pass "Fixed directory: $dir ($PERM → 700)"
      FIXED=$((FIXED + 1))
    else
      warn "Directory too open: $dir ($PERM, should be 700)"
      ISSUES=$((ISSUES + 1))
    fi
  fi
done < <(find "$OPENCLAW_PATH" -type d 2>/dev/null)

# Check sensitive files
info "Checking sensitive file permissions..."
while IFS= read -r file; do
  PERM=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
  if [[ "$PERM" != "600" ]]; then
    if [[ "$MODE" == "fix" ]]; then
      chmod 600 "$file"
      pass "Fixed file: $file ($PERM → 600)"
      FIXED=$((FIXED + 1))
    else
      warn "File too open: $file ($PERM, should be 600)"
      ISSUES=$((ISSUES + 1))
    fi
  fi
done < <(find "$OPENCLAW_PATH" -type f \( \
  -name "*.json" \
  -o -name "*.env" \
  -o -name "*.key" \
  -o -name "*.pem" \
  -o -name ".file-integrity-baseline" \
\) 2>/dev/null)

echo ""
if [[ "$MODE" == "fix" ]]; then
  echo "============================================================="
  echo " ✅ Fixed $FIXED items"
  echo " 📄 Log: $LOG"
  echo "============================================================="
else
  echo "============================================================="
  echo " Check complete: $ISSUES issue(s) found"
  echo " Run with --mode fix to repair"
  echo " 📄 Log: $LOG"
  echo "============================================================="
fi
