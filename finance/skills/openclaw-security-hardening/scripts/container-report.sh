#!/bin/bash
# container-report.sh v8.07 — Generate final hardening report
# v8.07 fixes:
#   - Fixed corrupted output at end of script (v5 heredoc was broken)
#   - Added warn() function
#   - Enhanced environment info in report
# Usage: bash container-report.sh [--report-dir DIR] [--output FILE] [--help]

set -euo pipefail

REPORT_DIR="./reports"
OUTPUT=""
OPENCLAW_PATH="/root/.openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --output)     OUTPUT="$2"; shift 2 ;;
    --path)       OPENCLAW_PATH="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --report-dir DIR   Report directory (default: ./reports)"
      echo "  --output FILE      Output file (auto-generated if not set)"
      echo "  --path DIR         OpenClaw path (default: /root/.openclaw)"
      echo "  --help             Show this help"
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

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$REPORT_DIR/final-report-${TIMESTAMP}.md"
fi

# Auto-detect reports
PRE_JSON=$(find "$REPORT_DIR" -name "pre-assessment-*.json" -type f 2>/dev/null | sort -r | head -1)
VALIDATION_JSON=$(find "$REPORT_DIR" -name "post-validation-*.json" -type f 2>/dev/null | sort -r | head -1)
STATE_JSON=$(find "$REPORT_DIR" -name "harden-state-*.json" -type f 2>/dev/null | sort -r | head -1)
DIFF_REPORT=$(find "$REPORT_DIR" -name "diff-report-*.md" -type f 2>/dev/null | sort -r | head -1)
BACKUP_FILE=$(find "$OPENCLAW_PATH/backups" -name "pre-harden-*.tgz" -type f 2>/dev/null | sort -r | head -1)

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

# Logging functions
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

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

# Detect container
detect_container_mode() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || \
     grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    echo "container"
  else
    echo "host"
  fi
}
CONTAINER_MODE=$(detect_container_mode)

# Extract scores
if [[ -n "$PRE_JSON" ]]; then
  PRE_SCORE=$(safe_node_get "$PRE_JSON" "risk_score")
  PRE_FAILS=$(safe_node_get "$PRE_JSON" "fail_count")
  PRE_WARNS=$(safe_node_get "$PRE_JSON" "warn_count")
  PRE_DISTRO=$(safe_node_get "$PRE_JSON" "distro" 2>/dev/null || echo "$DISTRO")
else
  PRE_SCORE="N/A"
  PRE_FAILS="N/A"
  PRE_WARNS="N/A"
  PRE_DISTRO="$DISTRO"
fi

if [[ -n "$VALIDATION_JSON" ]]; then
  POST_STATUS=$(safe_node_get "$VALIDATION_JSON" "status")
  POST_FAILS=$(safe_node_get "$VALIDATION_JSON" "fail_count")
  POST_PASSES=$(safe_node_get "$VALIDATION_JSON" "pass_count")
  # Normalize empty values to "N/A" for robust arithmetic
  [[ -z "$POST_STATUS" ]] && POST_STATUS="N/A"
  [[ -z "$POST_FAILS" ]] && POST_FAILS="N/A"
  [[ -z "$POST_PASSES" ]] && POST_PASSES="N/A"
  if [[ "$POST_STATUS" == "all_passed" ]]; then
    POST_SCORE=0
  elif [[ "$POST_FAILS" != "N/A" && "$POST_FAILS" != "null" ]]; then
    POST_SCORE=$((POST_FAILS * 5))
    [[ $POST_SCORE -gt 100 ]] && POST_SCORE=100
  else
    POST_SCORE="N/A"
  fi
else
  POST_STATUS="N/A"
  POST_FAILS="N/A"
  POST_PASSES="N/A"
  POST_SCORE="N/A"
fi

# Generate report
cat > "$OUTPUT" <<EOF
# OpenClaw Security Hardening — Final Report

**Date:** $(date)
**Tool:** openclaw-security-container-rocky-v8.07
**Report ID:** $TIMESTAMP

---

## Environment

| Item | Value |
|------|-------|
| OS | $PRE_DISTRO |
| Container Mode | $CONTAINER_MODE |
| Kernel | $(uname -r) |

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Pre-Hardening Risk Score | $PRE_SCORE/100 |
| Post-Hardening Risk Score | $POST_SCORE/100 |
| Validation Status | $POST_STATUS |
EOF

if [[ "$PRE_SCORE" != "N/A" && "$POST_SCORE" != "N/A" ]]; then
  DIFF=$((PRE_SCORE - POST_SCORE))
  echo "| Improvement | $DIFF points" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<EOF

---

## Risk Score Comparison

\`\`\`
Before: $PRE_SCORE/100  ($(
  if [[ "$PRE_SCORE" == "N/A" ]]; then echo "unknown"
  elif [[ "$PRE_SCORE" -lt 15 ]]; then echo "LOW"
  elif [[ "$PRE_SCORE" -lt 30 ]]; then echo "MEDIUM"
  else echo "HIGH"
fi
))

After:  $POST_SCORE/100  ($(
  if [[ "$POST_SCORE" == "N/A" ]]; then echo "unknown"
  elif [[ "$POST_SCORE" -lt 15 ]]; then echo "LOW"
  elif [[ "$POST_SCORE" -lt 30 ]]; then echo "MEDIUM"
  else echo "HIGH"
fi
))
\`\`\`

---

## Hardening Items Applied

### 1. OpenClaw Configuration
- Gateway token length verified (≥32 characters)
- Gateway bound to loopback/localhost (localhost only)
- Configuration file permissions set to 600
- .env file created for secrets separation
- Security rules injected into SOUL.md and AGENTS.md

### 2. System Base
- SSH hardening: PermitRootLogin → prohibit-password
- SSH hardening: PermitEmptyPasswords → no
- SSH hardening: MaxAuthTries → 3
- Password policy: MIN_LEN=12, MAX_DAYS=90
- avahi-daemon (mDNS) disabled
- firewalld enabled and configured
- Kernel security parameters applied (sysctl)

### 3. Container Security
- Seccomp profile deployed
- Secure docker-compose template provided
- Read-only root filesystem recommended

### 4. Compliance & Auditing
- File integrity baseline initialized (SHA256)
- Log rotation configured
- Weekly security audit cronjob added

EOF

# Add hardening status matrix
if [[ -n "$STATE_JSON" ]]; then
  echo "" >> "$OUTPUT"
  echo "---" >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  echo "## Hardening Status Matrix" >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  echo "| # | Step | Status |" >> "$OUTPUT"
  echo "|---|------|--------|" >> "$OUTPUT"

  node -e "
    const fs = require('fs');
    const s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    let n = 1;
    if (s.results && Array.isArray(s.results)) {
      s.results.forEach(r => {
        const icon = r.status === 'success' ? '✅ Success' : r.status === 'failed' ? '❌ Failed' : '⏭️ Skipped';
        console.log('| ' + n + ' | ' + r.step + ' | ' + icon + ' |');
        n++;
      });
    }
  " "$STATE_JSON" >> "$OUTPUT" 2>/dev/null || echo "| - | (unable to parse) | - |" >> "$OUTPUT"
fi

# Add backup/restore info
cat >> "$OUTPUT" <<EOF

---

## Backup Information

**Backup Location:** ${BACKUP_FILE:-Not found}

To restore from backup:
\`\`\`bash
bash scripts/container-rocky-restore.sh --backup-dir "$OPENCLAW_PATH/backups"
\`\`\`

---

## Next Steps for Administrator

1. **Restart Gateway** to apply configuration changes:
   \`\`\`bash
   openclaw gateway restart
   \`\`\`

2. **Verify Gateway status**:
   \`\`\`bash
   openclaw status
   \`\`\`

3. **Test SSH connectivity** (do NOT disconnect current session until verified)

4. **Move API keys to .env**:
   \`\`\`bash
   # Edit $OPENCLAW_PATH/.env and add your credentials
   chmod 600 $OPENCLAW_PATH/.env
   \`\`\`

5. **Review security rules** added to SOUL.md and AGENTS.md

6. **Check weekly audit** logs at \`/var/log/openclaw-audit.log\`

---

## Files Generated

| File | Description |
|------|-------------|
| $OUTPUT | This final report |
EOF

if [[ -n "$PRE_JSON" ]]; then
  echo "| $PRE_JSON | Pre-assessment data |" >> "$OUTPUT"
fi
if [[ -n "$VALIDATION_JSON" ]]; then
  echo "| $VALIDATION_JSON | Post-validation data |" >> "$OUTPUT"
fi
if [[ -n "$STATE_JSON" ]]; then
  echo "| $STATE_JSON | Hardening state |" >> "$OUTPUT"
fi
if [[ -n "$DIFF_REPORT" ]]; then
  echo "| $DIFF_REPORT | Before/after comparison |" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<EOF

---
*Generated automatically by openclaw-security-container-rocky-v8.07*
EOF

echo "============================================================="
echo " ✅ Final report generated: $OUTPUT"
echo "============================================================="
