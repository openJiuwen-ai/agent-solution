#!/bin/bash
# container-pre-post-diff.sh v8.07 — Compare pre-assessment vs post-hardening results
# v8.07 fixes:
#   - Added warn() function
#   - Enhanced container detection
# Usage: bash container-pre-post-diff.sh [--report-dir DIR] [--output FILE] [--help]

set -euo pipefail

REPORT_DIR="./reports"
OUTPUT=""
OPENCLAW_PATH="/root/.openclaw"

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

# Auto-detect reports
PRE_JSON=$(find "$REPORT_DIR" -name "pre-assessment-*.json" -type f 2>/dev/null | sort -r | head -1)
PRE_MD=$(find "$REPORT_DIR" -name "pre-assessment-*.md" -type f 2>/dev/null | sort -r | head -1)
VALIDATION_JSON=$(find "$REPORT_DIR" -name "post-validation-*.json" -type f 2>/dev/null | sort -r | head -1)
STATE_JSON=$(find "$REPORT_DIR" -name "harden-state-*.json" -type f 2>/dev/null | sort -r | head -1)

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

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$REPORT_DIR/diff-report-${TIMESTAMP}.md"
fi

echo "============================================================="
echo " Pre/Post Hardening Comparison v8"
echo "============================================================="
echo ""

# Extract values from pre-assessment
if [[ -n "$PRE_JSON" ]]; then
  echo "  Pre-assessment:  $(basename "$PRE_JSON")"
  PRE_SCORE=$(safe_node_get "$PRE_JSON" "risk_score")
  PRE_TOKEN=$(safe_node_get "$PRE_JSON" "token_length")
  PRE_BIND=$(safe_node_get "$PRE_JSON" "bind_address")
  PRE_PERM=$(safe_node_get "$PRE_JSON" "config_permissions")
  PRE_DIR_PERM=$(safe_node_get "$PRE_JSON" "dir_permissions")
  PRE_FAILS=$(safe_node_get "$PRE_JSON" "fail_count")
  PRE_WARNS=$(safe_node_get "$PRE_JSON" "warn_count")
  PRE_PASSES=$(safe_node_get "$PRE_JSON" "pass_count")
  # Normalize empty values to "N/A" for robust arithmetic
  [[ -z "$PRE_SCORE" ]] && PRE_SCORE="N/A"
  [[ -z "$PRE_TOKEN" ]] && PRE_TOKEN="N/A"
  [[ -z "$PRE_BIND" ]] && PRE_BIND="N/A"
  [[ -z "$PRE_PERM" ]] && PRE_PERM="N/A"
  [[ -z "$PRE_DIR_PERM" ]] && PRE_DIR_PERM="N/A"
  [[ -z "$PRE_FAILS" ]] && PRE_FAILS="N/A"
  [[ -z "$PRE_WARNS" ]] && PRE_WARNS="N/A"
  [[ -z "$PRE_PASSES" ]] && PRE_PASSES="N/A"
else
  warn "No pre-assessment found — generate one first"
  PRE_SCORE="N/A"
  PRE_TOKEN="N/A"
  PRE_BIND="N/A"
  PRE_PERM="N/A"
  PRE_DIR_PERM="N/A"
  PRE_FAILS="N/A"
  PRE_WARNS="N/A"
  PRE_PASSES="N/A"
fi

# Extract values from post-validation
if [[ -n "$VALIDATION_JSON" ]]; then
  echo "  Post-validation: $(basename "$VALIDATION_JSON")"
  POST_STATUS=$(safe_node_get "$VALIDATION_JSON" "status")
  POST_FAILS=$(safe_node_get "$VALIDATION_JSON" "fail_count")
  POST_PASSES=$(safe_node_get "$VALIDATION_JSON" "pass_count")
  # Normalize empty values
  [[ -z "$POST_STATUS" ]] && POST_STATUS="N/A"
  [[ -z "$POST_FAILS" ]] && POST_FAILS="N/A"
  [[ -z "$POST_PASSES" ]] && POST_PASSES="N/A"
else
  warn "No post-validation found — run hardening first"
  POST_STATUS="N/A"
  POST_FAILS="N/A"
  POST_PASSES="N/A"
fi

# Extract current values from live system
JSON_FILE="$OPENCLAW_PATH/openclaw.json"
if [[ -f "$JSON_FILE" ]]; then
  CUR_TOKEN=$(node -e "
    const fs = require('fs');
    const p = process.argv[1];
    try { const c = JSON.parse(fs.readFileSync(p, 'utf8')); console.log((c.gateway?.auth?.token || c.gateway?.token || '').length || 0); }
    catch(e) { console.log(0); }
  " "$JSON_FILE" 2>/dev/null || echo "0")
  CUR_BIND=$(node -e "
    const fs = require('fs');
    const p = process.argv[1];
    try { const c = JSON.parse(fs.readFileSync(p, 'utf8')); console.log(c.gateway?.bind || ''); }
    catch(e) { console.log(''); }
  " "$JSON_FILE" 2>/dev/null || echo "")
  CUR_PERM=$(stat -c "%a" "$JSON_FILE" 2>/dev/null || echo "N/A")
  CUR_DIR_PERM=$(stat -c "%a" "$OPENCLAW_PATH" 2>/dev/null || echo "N/A")
else
  CUR_TOKEN="N/A"
  CUR_BIND="N/A"
  CUR_PERM="N/A"
  CUR_DIR_PERM="N/A"
fi

# Compute post-score (based on post-validation)
if [[ "$POST_STATUS" == "all_passed" ]]; then
  POST_SCORE=0
elif [[ "$POST_FAILS" != "N/A" && "$POST_FAILS" =~ ^[0-9]+$ ]]; then
  POST_SCORE=$((POST_FAILS * 5))
  if [[ $POST_SCORE -gt 100 ]]; then POST_SCORE=100; fi
else
  POST_SCORE="N/A"
fi

echo ""
echo "  Pre-Score:  $PRE_SCORE/100"
echo "  Post-Score: $POST_SCORE/100"
echo ""

# ---- Generate Markdown Report ----
cat > "$OUTPUT" <<EOF
# OpenClaw Hardening — Before & After Comparison

**Date:** $(date)
**Report ID:** $TIMESTAMP

## Risk Score

| Stage | Score | Fails | Warns | Passes |
|-------|-------|-------|-------|--------|
| **Before** | $PRE_SCORE/100 | $PRE_FAILS | $PRE_WARNS | $PRE_PASSES |
| **After**  | $POST_SCORE/100 | $POST_FAILS | - | $POST_PASSES |

$(
  if [[ "$PRE_SCORE" != "N/A" && "$POST_SCORE" != "N/A" ]]; then
    DIFF=$((PRE_SCORE - POST_SCORE))
    if [[ $DIFF -gt 0 ]]; then
      echo "**Improvement: Risk score reduced by $DIFF points** ✅"
    elif [[ $DIFF -eq 0 ]]; then
      echo "No change in risk score"
    else
      echo "**Warning: Risk score increased by $((-DIFF)) points** ⚠️"
    fi
  fi
)

## Detailed Comparison

| Check | Before | After | Status |
|-------|--------|-------|--------|
| Token Length | ${PRE_TOKEN} | $CUR_TOKEN | $([ "$CUR_TOKEN" != "0" ] && [ "$CUR_TOKEN" != "N/A" ] && echo "✅" || echo "⚠️") |
| Bind Address | ${PRE_BIND} | $CUR_BIND | $([ "$CUR_BIND" = "127.0.0.1" ] || [ "$CUR_BIND" = "loopback" ] || [ "$CUR_BIND" = "localhost" ] && echo "✅" || echo "⚠️") |
| Config Permissions | ${PRE_PERM} | $CUR_PERM | $([ "$CUR_PERM" = "600" ] && echo "✅" || echo "⚠️") |
| Dir Permissions | ${PRE_DIR_PERM} | $CUR_DIR_PERM | $([ "${CUR_DIR_PERM:0:1}" = "7" ] && echo "✅" || echo "⚠️") |

EOF

# Append hardening status matrix if state file exists
if [[ -n "$STATE_JSON" ]]; then
  echo "" >> "$OUTPUT"
  echo "## Hardening Status Matrix" >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  echo "| Step | Status |" >> "$OUTPUT"
  echo "|------|--------|" >> "$OUTPUT"

  node -e "
    const fs = require('fs');
    const s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    if (s.results && Array.isArray(s.results)) {
      s.results.forEach(r => {
        const icon = r.status === 'success' ? '✅' : r.status === 'failed' ? '❌' : '⏭️';
        console.log('| ' + r.step + ' | ' + icon + ' ' + r.status + ' |');
      });
    }
  " "$STATE_JSON" >> "$OUTPUT" 2>/dev/null || echo "| (unable to parse state) | - |" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<EOF

## Validation Result
**Post-Hardening Status:** $POST_STATUS

---
*Generated by openclaw-security-container-rocky-v8.07*
EOF

echo "📄 Diff report written to: $OUTPUT"
echo ""
echo "============================================================="
echo " ✅ Comparison Complete"
echo "============================================================="
