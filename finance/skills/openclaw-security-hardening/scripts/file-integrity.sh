#!/bin/bash
# file-integrity.sh v8.07 — File integrity baseline management
# v8.07 fixes:
#   - JSON generation fixed: use node to build entire JSON (v5 used bash subshell which lost variable state)
#   - Verification fixed: read baseline via node to avoid subshell issues
# Usage: bash file-integrity.sh --mode create|verify --path DIR [--baseline FILE]

set -euo pipefail

MODE="create"
OPENCLAW_PATH="/root/.openclaw"
BASELINE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     MODE="$2"; shift 2 ;;
    --path)     OPENCLAW_PATH="$2"; shift 2 ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 --mode create|verify --path DIR [--baseline FILE]"
      echo "  --mode create     Create a new integrity baseline"
      echo "  --mode verify     Verify files against existing baseline"
      echo "  --path DIR        OpenClaw install path (default: /root/.openclaw)"
      echo "  --baseline FILE   Baseline file path (auto-generated if not set)"
      echo "  --help            Show this help"
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

if [[ -z "$BASELINE" ]]; then
  BASELINE="$OPENCLAW_PATH/.file-integrity-baseline"
fi

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
pass() { echo -e "\033[1;32m[PASS]\033[0m $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

case "$MODE" in
  create)
    info "Creating file integrity baseline..."
    info "Target: $OPENCLAW_PATH"
    info "Output: $BASELINE"

    # v6 FIX: Use node to generate entire JSON — avoids bash subshell variable scope issue
    # In v5, the while loop inside a pipe created a subshell, so FIRST variable never changed
    cd "$OPENCLAW_PATH"
    
    # Collect file list and hashes, then let node build the JSON
    FILE_LIST=$(find . -type f \
      -not -path "./node_modules/*" \
      -not -path "./backups/*" \
      -not -path "./.file-integrity-baseline" \
      -not -path "./logs/*" \
      2>/dev/null | sort)

    if [[ -z "$FILE_LIST" ]]; then
      warn "No files found to hash"
      echo '{"version":"8.07","created":"'"$(date -Iseconds)"'","root":"'"$OPENCLAW_PATH"'","files":{}}' > "$BASELINE"
    else
      # Build "filepath hash" pairs to temp file (avoid broken pipe from while|node)
      TMP_HASH=$(mktemp /tmp/hash-XXXXXX)
      while IFS= read -r file; do
        HASH=$(sha256sum "$file" | awk '{print $1}')
        REL_PATH="${file#./}"
        printf '%s\t%s\n' "$REL_PATH" "$HASH"
      done <<< "$FILE_LIST" > "$TMP_HASH"
      node -e "
        const fs = require('fs');
        const input = fs.readFileSync(process.argv[1], 'utf8').trim();
        const files = {};
        if (input) {
          for (const line of input.split('\\n')) {
            const [path, hash] = line.split('\\t');
            if (path && hash) files[path] = hash;
          }
        }
        const baseline = {
          version: '8.07',
          created: new Date().toISOString(),
          root: process.argv[2],
          files: files
        };
        fs.writeFileSync(process.argv[2], JSON.stringify(baseline, null, 2) + '\\n');
      " "$TMP_HASH" "$BASELINE" 2>/dev/null
      rm -f "$TMP_HASH"
    fi

    FILE_COUNT=$(find "$OPENCLAW_PATH" -type f \
      -not -path "*/node_modules/*" \
      -not -path "*/backups/*" \
      -not -path "*/.file-integrity-baseline" \
      -not -path "*/logs/*" \
      2>/dev/null | wc -l)

    if [[ -f "$BASELINE" ]]; then
      pass "Baseline created: $BASELINE ($FILE_COUNT files)"
    else
      fail "Baseline creation failed"
    fi
    ;;

  verify)
    info "Verifying file integrity against baseline..."
    info "Baseline: $BASELINE"

    if [[ ! -f "$BASELINE" ]]; then
      fail "Baseline file not found: $BASELINE"
      echo "  Run with --mode create first"
      exit 1
    fi

    cd "$OPENCLAW_PATH"

    # v6 FIX: Use node to do the entire verification — avoids subshell variable loss
    VERIFICATION_RESULT=$(node -e "
      const fs = require('fs');
      const { execSync } = require('child_process');

      const baseline = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
      const files = baseline.files || {};
      const results = { total: 0, ok: 0, changed: 0, missing: 0 };

      for (const [file, expectedHash] of Object.entries(files)) {
        results.total++;
        if (!fs.existsSync(file)) {
          results.missing++;
          console.log('MISSING: ' + file);
          continue;
        }
        try {
          const actualHash = execSync('sha256sum ' + JSON.stringify(file), {encoding:'utf8'})
            .trim().split(/\\s+/)[0];
          if (actualHash === expectedHash) {
            results.ok++;
          } else {
            results.changed++;
            console.log('CHANGED: ' + file);
          }
        } catch(e) {
          results.missing++;
          console.log('ERROR: ' + file + ' - ' + e.message);
        }
      }

      console.log('\\n---SUMMARY---');
      console.log(JSON.stringify(results));
    " "$BASELINE" 2>/dev/null)

    echo "$VERIFICATION_RESULT" | grep -v "^---SUMMARY---"
    SUMMARY=$(echo "$VERIFICATION_RESULT" | grep "^---SUMMARY---" -A1 | tail -1)
    
    TOTAL=$(echo "$SUMMARY" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); try{const j=JSON.parse(d);console.log(j.total||0)}catch(e){console.log(0)}")
    OK=$(echo "$SUMMARY" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); try{const j=JSON.parse(d);console.log(j.ok||0)}catch(e){console.log(0)}")
    CHANGED=$(echo "$SUMMARY" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); try{const j=JSON.parse(d);console.log(j.changed||0)}catch(e){console.log(0)}")
    MISSING=$(echo "$SUMMARY" | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); try{const j=JSON.parse(d);console.log(j.missing||0)}catch(e){console.log(0)}")

    echo ""
    info "Verification complete"
    echo "  Total: $TOTAL | OK: $OK | Changed: $CHANGED | Missing: $MISSING"

    if [[ $CHANGED -eq 0 && $MISSING -eq 0 ]]; then
      pass "All files match baseline — integrity verified"
      exit 0
    else
      fail "$CHANGED file(s) changed, $MISSING file(s) missing"
      exit 1
    fi
    ;;

  *)
    fail "Unknown mode: $MODE"
    echo "  Use --mode create or --mode verify"
    exit 1
    ;;
esac
