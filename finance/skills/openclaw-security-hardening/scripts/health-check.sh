#!/bin/bash
# health-check.sh v8 - Quick daily health check for OpenClaw
# Usage: bash health-check.sh [--path DIR] [--json] [--help]
#
# v8 changes:
# - Use jq when available (much faster than node for JSON parsing)
# - Add Gateway HTTP reachability check (9th check)
# - Add process uptime check (10th check)
# - Improved color output and summary

set -euo pipefail

OPENCLAW_PATH="/root/.openclaw"
OUTPUT_JSON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) OPENCLAW_PATH="$2"; shift 2 ;;
    --json) OUTPUT_JSON=true; shift ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --path DIR   OpenClaw install path (default: /root/.openclaw)"
      echo "  --json       Output in JSON format"
      echo "  --help       Show this help"
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

JSON_FILE="$OPENCLAW_PATH/openclaw.json"

# JSON reader: prefer jq, fall back to node
json_val() {
  local file="$1"
  local path="$2"
  if command -v jq &>/dev/null; then
    jq -r ".$path // empty" "$file" 2>/dev/null || echo ""
  else
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
    " "$file" "$path" 2>/dev/null || echo ""
  fi
}

# Check result arrays
CHECKS=()
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  case "$status" in
    pass) CHECKS+=("pass|$name|$detail"); ((PASS_COUNT++)) || true ;;
    fail) CHECKS+=("fail|$name|$detail"); ((FAIL_COUNT++)) || true ;;
    warn) CHECKS+=("warn|$name|$detail"); ((WARN_COUNT++)) || true ;;
  esac
}

# 1. Config file exists
if [[ -f "$JSON_FILE" ]]; then
  check "Config file" "pass" "$JSON_FILE"
else
  check "Config file" "fail" "openclaw.json not found at $OPENCLAW_PATH"
  # Can't continue without config
  check "Token length" "fail" "config missing"
  check "Bind address" "fail" "config missing"
  check "Config permissions" "fail" "config missing"
  check ".env file" "warn" "skipped (config missing)"
  check "File integrity" "warn" "skipped (config missing)"
  check "Audit log" "warn" "skipped (config missing)"
  check "Backups" "warn" "skipped (config missing)"
  check "Gateway HTTP" "warn" "skipped (config missing)"
  check "Process uptime" "warn" "skipped (config missing)"
fi

# 2. Token length (only if config exists)
if [[ -f "$JSON_FILE" ]]; then
  TOKEN=$(json_val "$JSON_FILE" "gateway.auth.token")
  if [[ -z "$TOKEN" ]]; then
    TOKEN=$(json_val "$JSON_FILE" "gateway.token")
  fi
  if [[ ${#TOKEN} -ge 32 ]]; then
    check "Token length" "pass" "${#TOKEN} chars"
  elif [[ ${#TOKEN} -gt 0 ]]; then
    check "Token length" "fail" "${#TOKEN} chars (need >=32)"
  else
    check "Token length" "fail" "empty/not set"
  fi
fi

# 3. Bind address (only if config exists)
if [[ -f "$JSON_FILE" ]]; then
  BIND=$(json_val "$JSON_FILE" "gateway.bind")
  if [[ "$BIND" == "127.0.0.1" || "$BIND" == "localhost" || "$BIND" == "loopback" ]]; then
    check "Bind address" "pass" "$BIND"
  elif [[ -n "$BIND" ]]; then
    check "Bind address" "fail" "$BIND (should be loopback/localhost)"
  else
    check "Bind address" "fail" "not set (should be loopback/localhost)"
  fi
fi

# 4. Config permissions (only if config exists)
if [[ -f "$JSON_FILE" ]]; then
  PERM=$(stat -c "%a" "$JSON_FILE" 2>/dev/null || echo "000")
  if [[ "$PERM" == "600" ]]; then
    check "Config permissions" "pass" "$PERM"
  else
    check "Config permissions" "fail" "$PERM (should be 600)"
  fi
fi

# 5. .env file
if [[ -f "$JSON_FILE" ]]; then
  if [[ -f "$OPENCLAW_PATH/.env" ]]; then
    ENV_PERM=$(stat -c "%a" "$OPENCLAW_PATH/.env" 2>/dev/null || echo "000")
    if [[ "$ENV_PERM" == "600" ]]; then
      check ".env file" "pass" "exists, perm $ENV_PERM"
    else
      check ".env file" "warn" "exists but perm $ENV_PERM (should be 600)"
    fi
  else
    check ".env file" "warn" "not found (consider creating)"
  fi
fi

# 6. File integrity baseline
if [[ -f "$JSON_FILE" ]]; then
  if [[ -f "$OPENCLAW_PATH/.file-integrity-baseline" ]]; then
    check "File integrity" "pass" "baseline exists"
  else
    check "File integrity" "fail" "baseline missing"
  fi
fi

# 7. Audit log
if [[ -f "$JSON_FILE" ]]; then
  AUDIT_LOG="/var/log/openclaw-audit.log"
  if [[ -f "$AUDIT_LOG" ]]; then
    LAST_AUDIT=$(stat -c "%Y" "$AUDIT_LOG" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    AGE_DAYS=$(( (NOW - LAST_AUDIT) / 86400 ))
    if [[ $AGE_DAYS -le 7 ]]; then
      check "Audit log" "pass" "$AGE_DAYS days ago"
    else
      check "Audit log" "warn" "$AGE_DAYS days ago (should be <7)"
    fi
  else
    check "Audit log" "warn" "no audit log found"
  fi
fi

# 8. Backups
if [[ -f "$JSON_FILE" ]]; then
  BACKUP_COUNT=$(find "$OPENCLAW_PATH/backups" -name "pre-harden-*.tgz" -type f 2>/dev/null | wc -l)
  if [[ $BACKUP_COUNT -gt 0 ]]; then
    check "Backups" "pass" "$BACKUP_COUNT backup(s)"
  else
    check "Backups" "warn" "no backups"
  fi
fi

# 9. Gateway HTTP reachability (v8 new)
if [[ -f "$JSON_FILE" ]]; then
  BIND=$(json_val "$JSON_FILE" "gateway.bind")
  PORT=$(json_val "$JSON_FILE" "gateway.port")
  PORT=${PORT:-7437}
  if curl -sf --connect-timeout 3 "http://127.0.0.1:${PORT}/" &>/dev/null; then
    check "Gateway HTTP" "pass" "reachable on :${PORT}"
  elif [[ "$BIND" == "127.0.0.1" || "$BIND" == "localhost" || "$BIND" == "loopback" ]]; then
    check "Gateway HTTP" "warn" "not reachable on :${PORT} (Gateway may be stopped)"
  else
    check "Gateway HTTP" "warn" "bind=${BIND:-unset}, port=${PORT}"
  fi
fi

# 10. Process uptime (v8 new)
GW_PID=$(pgrep -f "openclaw" 2>/dev/null | head -1 || true)
if [[ -n "$GW_PID" ]]; then
  UPTIME_SEC=$(( $(date +%s) - $(stat -c "%Y" "/proc/$GW_PID" 2>/dev/null || echo "0") ))
  if [[ $UPTIME_SEC -gt 0 ]]; then
    UPTIME_HOURS=$(( UPTIME_SEC / 3600 ))
    check "Process uptime" "pass" "${UPTIME_HOURS}h (PID $GW_PID)"
  else
    check "Process uptime" "pass" "running (PID $GW_PID)"
  fi
else
  check "Process uptime" "warn" "Gateway process not found"
fi

# ===== Output =====
if $OUTPUT_JSON; then
  # Build JSON output
  echo "{"
  echo "  \"type\": \"health-check\","
  echo "  \"version\": \"8.0\","
  echo "  \"timestamp\": \"$(date -Iseconds)\","
  echo "  \"openclaw_path\": \"$OPENCLAW_PATH\","
  echo "  \"json_parser\": \"$(command -v jq &>/dev/null && echo 'jq' || echo 'node')\","
  echo "  \"pass\": $PASS_COUNT,"
  echo "  \"fail\": $FAIL_COUNT,"
  echo "  \"warn\": $WARN_COUNT,"
  echo "  \"checks\": ["
  FIRST=true
  for c in "${CHECKS[@]}"; do
    IFS='|' read -r status name detail <<< "$c"
    $FIRST || echo ","
    FIRST=false
    printf '    {"name":"%s","status":"%s","detail":"%s"}' "$name" "$status" "$detail"
  done
  echo ""
  echo "  ]"
  echo "}"
else
  echo "============================================================="
  echo " 🦫 OpenClaw Health Check v8"
  echo "============================================================="
  echo ""
  for c in "${CHECKS[@]}"; do
    IFS='|' read -r status name detail <<< "$c"
    case "$status" in
      pass) echo -e "  ✅ $name: $detail" ;;
      fail) echo -e "  ❌ $name: $detail" ;;
      warn) echo -e "  ⚠️  $name: $detail" ;;
    esac
  done
  echo ""
  echo "============================================================="
  echo " PASS: $PASS_COUNT | FAIL: $FAIL_COUNT | WARN: $WARN_COUNT | TOTAL: $((PASS_COUNT + FAIL_COUNT + WARN_COUNT))"
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo " ✅ Overall: HEALTHY"
  else
    echo " ❌ Overall: ISSUES DETECTED ($FAIL_COUNT failures)"
  fi
  echo "============================================================="
fi

exit $FAIL_COUNT
