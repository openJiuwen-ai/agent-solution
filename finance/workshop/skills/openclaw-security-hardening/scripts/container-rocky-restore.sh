#!/bin/bash
# container-rocky-restore.sh v8.07 — Restore OpenClaw to pre-hardening state
# v8.07 fixes:
#   - Fixed $REPORT_F → $REPORT_FILE typo (v5 bug)
#   - Fixed while loop in pipe → use process substitution (v5 variable loss)
#   - Added warn() function
#   - Enhanced container detection
# Usage: bash container-rocky-restore.sh [--backup-dir DIR] [--help]

set -euo pipefail

# Defaults
BACKUP_DIR=""
OPENCLAW_PATH="/root/.openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="./reports"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --path)       OPENCLAW_PATH="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --backup-dir DIR  Directory containing backup files (default: auto-detect)"
      echo "  --path DIR        OpenClaw install path (default: /root/.openclaw)"
      echo "  --report-dir DIR  Report output directory (default: ./reports)"
      echo "  --help            Show this help"
      echo ""
      echo "This script restores OpenClaw to its pre-hardening state."
      echo "It REQUIRES manual confirmation before making any changes."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

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

# Logging functions — v6: warn() defined
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
pass()  { echo -e "\033[1;32m[PASS]\033[0m $*"; }
fail()  { echo -e "\033[1;31m[FAIL]\033[0m $*"; }

echo "============================================================="
echo " OpenClaw Security Restore v8"
echo "============================================================="
echo " Mode: $CONTAINER_MODE"
echo ""

# ---- Step 1: Auto-detect backup dir if not specified ----
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$OPENCLAW_PATH/backups"
  info "Auto-detected backup directory: $BACKUP_DIR"
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  fail "Backup directory not found: $BACKUP_DIR"
  echo "  Create it or specify with --backup-dir"
  exit 1
fi

# ---- Step 2: List available backups ----
info "Scanning for available backup files..."
mapfile -t BACKUP_FILES < <(find "$BACKUP_DIR" -name "pre-harden-*.tgz" -type f 2>/dev/null | sort -r)

if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
  fail "No backup files found in $BACKUP_DIR"
  echo "  Backups are created by container-rocky-harden.sh"
  exit 1
fi

echo ""
echo "Available backups:"
echo "-------------------------------------------------------------"
for i in "${!BACKUP_FILES[@]}"; do
  idx=$((i + 1))
  fname=$(basename "${BACKUP_FILES[$i]}")
  fsize=$(stat -c "%s" "${BACKUP_FILES[$i]}" 2>/dev/null || echo "?")
  fdate=$(stat -c "%y" "${BACKUP_FILES[$i]}" 2>/dev/null | cut -d'.' -f1)
  echo "  [$idx] $fname"
  echo "      Size: ${fsize}B | Modified: $fdate"
done
echo "-------------------------------------------------------------"
echo ""

# ---- Step 3: Select backup ----
read -p "Select backup number to restore from [1-${#BACKUP_FILES[@]}]: " SELECT_NUM

if ! [[ "$SELECT_NUM" =~ ^[0-9]+$ ]] || [[ "$SELECT_NUM" -lt 1 ]] || [[ "$SELECT_NUM" -gt "${#BACKUP_FILES[@]}" ]]; then
  fail "Invalid selection: $SELECT_NUM"
  exit 1
fi

SELECTED_BACKUP="${BACKUP_FILES[$((SELECT_NUM - 1))]}"
info "Selected: $(basename "$SELECTED_BACKUP")"
# v8: Verify backup integrity before restore
if [[ -f "$SELECTED_BACKUP.sha256" ]]; then
  info "Verifying backup integrity..."
  if (cd "$(dirname "$SELECTED_BACKUP")" && sha256sum -c "$(basename "$SELECTED_BACKUP").sha256" >/dev/null 2>&1); then
    pass "Backup integrity verified (SHA256 match)"
  else
    fail "Backup integrity check FAILED - file may be corrupted"
    echo "  Use a different backup or re-run hardening to create a fresh backup"
    exit 1
  fi
fi

# ---- Step 4: Show backup contents ----
echo ""
info "Backup contents:"
tar -tzf "$SELECTED_BACKUP" 2>/dev/null || echo "  (unable to list contents)"
echo ""

# ---- Step 5: Select restore scope ----
echo "Restore categories:"
echo "  [1] All (full restore)"
echo "  [2] SSH only (sshd_config)"
echo "  [3] OpenClaw only (openclaw.json, .env, SOUL.md, AGENTS.md)"
echo "  [4] System parameters only (sysctl, login.defs)"
echo "  [5] Custom (select individual files)"
echo ""
read -p "Select restore category [1-5]: " RESTORE_CAT

case "$RESTORE_CAT" in
  1) RESTORE_MODE="all" ;;
  2) RESTORE_MODE="ssh" ;;
  3) RESTORE_MODE="openclaw" ;;
  4) RESTORE_MODE="system" ;;
  5) RESTORE_MODE="custom" ;;
  *) fail "Invalid category"; exit 1 ;;
esac

# ---- Step 6: CRITICAL — Manual Confirmation ----
echo ""
echo "============================================================="
echo " ⚠️  CONFIRMATION REQUIRED"
echo "============================================================="
echo ""
echo " You are about to RESTORE system configuration files to their"
echo " pre-hardening state. This will:"
echo ""

case "$RESTORE_MODE" in
  all)
    echo "   • Restore SSH configuration (may affect remote access)"
    echo "   • Restore OpenClaw configuration (may revert security fixes)"
    echo "   • Restore system parameters (sysctl, login.defs)"
    ;;
  ssh)
    echo "   • Restore SSH configuration (sshd_config)"
    echo "   • This may affect remote login security"
    ;;
  openclaw)
    echo "   • Restore openclaw.json, .env, SOUL.md, AGENTS.md"
    echo "   • This will revert OpenClaw security changes"
    ;;
  system)
    echo "   • Restore sysctl parameters and password policy"
    echo "   • This will revert system-level hardening"
    ;;
  custom)
    echo "   • Restore individually selected files"
    ;;
esac

echo ""
echo " This action CANNOT be undone without a new backup."
echo " After restore, you should run container-restore-validate.sh"
echo " to verify the restoration was successful."
echo ""

read -p 'Type YES to confirm restore: ' CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo ""
  info "Restore cancelled by user."
  exit 0
fi

# ---- Step 7: Pre-restore backup (safety net) ----
echo ""
info "Creating pre-restore safety backup..."
PRE_RESTORE_BACKUP="$BACKUP_DIR/pre-restore-${TIMESTAMP}.tgz"
mkdir -p "$BACKUP_DIR"

# Build backup paths for only existing files
PRE_RESTORE_PATHS=()
for f in etc/ssh/sshd_config etc/sysctl.d/99-openclaw-security.conf \
         etc/login.defs "$OPENCLAW_PATH/openclaw.json" \
         "$OPENCLAW_PATH/.env" \
         "$OPENCLAW_PATH/workspace/SOUL.md" \
         "$OPENCLAW_PATH/workspace/AGENTS.md"; do
  if [[ -f "$f" ]]; then
    PRE_RESTORE_PATHS+=("${f#/}")
  fi
done

if [[ ${#PRE_RESTORE_PATHS[@]} -gt 0 ]]; then
  tar -czf "$PRE_RESTORE_BACKUP" -C / "${PRE_RESTORE_PATHS[@]}" 2>/dev/null || true
else
  touch "$PRE_RESTORE_BACKUP"
fi

PASS_COUNT=0
if [[ -f "$PRE_RESTORE_BACKUP" ]]; then
  pass "Pre-restore safety backup: $PRE_RESTORE_BACKUP"
fi

# ---- Step 8: Execute restore ----
echo ""
info "Executing restore..."
RESTORE_LOG="$REPORT_DIR/restore-log-${TIMESTAMP}.txt"

do_restore() {
  local file="$1"
  local label="$2"

  # Check if file exists in the backup (strip leading / for comparison)
  local rel_file="${file#/}"
  if tar -tzf "$SELECTED_BACKUP" 2>/dev/null | grep -q "$rel_file"; then
    tar -xzf "$SELECTED_BACKUP" -C / "$rel_file" 2>/dev/null
    pass "Restored: $label"
    echo "[RESTORED] $label" >> "$RESTORE_LOG"
  else
    warn "Not in backup: $label (skipped)"
    echo "[SKIPPED] $label" >> "$RESTORE_LOG"
  fi
}

> "$RESTORE_LOG"  # Initialize log

case "$RESTORE_MODE" in
  all)
    do_restore "etc/ssh/sshd_config" "SSH configuration"
    do_restore "etc/sysctl.d/99-openclaw-security.conf" "sysctl parameters"
    do_restore "etc/login.defs" "password policy"
    do_restore "${OPENCLAW_PATH#/}/openclaw.json" "OpenClaw config"
    do_restore "${OPENCLAW_PATH#/}/.env" "OpenClaw .env"
    do_restore "${OPENCLAW_PATH#/}/workspace/SOUL.md" "SOUL.md"
    do_restore "${OPENCLAW_PATH#/}/workspace/AGENTS.md" "AGENTS.md"
    ;;
  ssh)
    do_restore "etc/ssh/sshd_config" "SSH configuration"
    ;;
  openclaw)
    do_restore "${OPENCLAW_PATH#/}/openclaw.json" "OpenClaw config"
    do_restore "${OPENCLAW_PATH#/}/.env" "OpenClaw .env"
    do_restore "${OPENCLAW_PATH#/}/workspace/SOUL.md" "SOUL.md"
    do_restore "${OPENCLAW_PATH#/}/workspace/AGENTS.md" "AGENTS.md"
    ;;
  system)
    do_restore "etc/sysctl.d/99-openclaw-security.conf" "sysctl parameters"
    do_restore "etc/login.defs" "password policy"
    ;;
  custom)
    echo "Available files in backup:"
    tar -tzf "$SELECTED_BACKUP" 2>/dev/null
    echo ""
    read -p "Enter file path to restore (or 'all'): " CUSTOM_FILE
    if [[ "$CUSTOM_FILE" == "all" ]]; then
      tar -xzf "$SELECTED_BACKUP" -C / 2>/dev/null
      pass "All files restored"
    else
      do_restore "$CUSTOM_FILE" "Custom: $CUSTOM_FILE"
    fi
    ;;
esac

# ---- Step 9: Restart services ----
echo ""
info "Restarting services to apply restored configuration..."

# Apply restored sysctl
if [[ -f /etc/sysctl.d/99-openclaw-security.conf ]] && [[ "$RESTORE_MODE" == "all" || "$RESTORE_MODE" == "system" ]]; then
  if command -v sysctl &>/dev/null; then
    sysctl -p /etc/sysctl.d/99-openclaw-security.conf >/dev/null 2>&1 || true
    pass "sysctl parameters reloaded"
  fi
fi

# Restart sshd if SSH was restored
if [[ "$RESTORE_MODE" == "all" || "$RESTORE_MODE" == "ssh" ]]; then
  if command -v sshd &>/dev/null && sshd -t 2>/dev/null; then
    if command -v systemctl &>/dev/null; then
      systemctl restart sshd 2>/dev/null || true
    fi
    pass "sshd restarted"
  else
    warn "sshd not available or config invalid after restore — check manually"
  fi
fi

# ---- Step 10: Run restore validation ----
echo ""
info "Running post-restore validation..."
set +e
bash "$SCRIPT_DIR/container-restore-validate.sh" \
  --backup-file "$SELECTED_BACKUP" \
  --report-dir "$REPORT_DIR"
VALIDATE_EXIT=$?
set -e

# ---- Step 11: Generate restore report ----
REPORT_FILE="$REPORT_DIR/restore-report-${TIMESTAMP}.md"
cat > "$REPORT_FILE" <<EOF
# OpenClaw Restore Report

**Date:** $(date)
**Backup Used:** $(basename "$SELECTED_BACKUP")
**Restore Mode:** $RESTORE_MODE
**Container Mode:** $CONTAINER_MODE

## Restore Summary

| Category | Status |
|----------|--------|
EOF

# v6 FIX: use process substitution instead of pipe to avoid subshell variable loss
while IFS= read -r line; do
  status=$(echo "$line" | grep -oE '\[(RESTORED|SKIPPED)\]' | tr -d '[]')
  item=$(echo "$line" | sed 's/^\[[A-Z]*\] //')
  if [[ "$status" == "RESTORED" ]]; then
    echo "| $item | ✅ Restored |" >> "$REPORT_FILE"
  else
    echo "| $item | ⏭️ Skipped (not in backup) |" >> "$REPORT_FILE"
  fi
done < <(grep -E "\[(RESTORED|SKIPPED)\]" "$RESTORE_LOG" 2>/dev/null || true)

cat >> "$REPORT_FILE" <<EOF

## Pre-Restore Safety Backup
- Location: $PRE_RESTORE_BACKUP
- Use this if the restore causes issues

## Restore Log
See: $RESTORE_LOG

## Validation Result
EOF

if [[ $VALIDATE_EXIT -eq 0 ]]; then
  echo "✅ Restore validation PASSED" >> "$REPORT_FILE"
else
  echo "⚠️ Restore validation had issues — review validation report" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

## Next Steps
1. Verify OpenClaw is functioning: \`openclaw status\`
2. Verify SSH connectivity (do NOT disconnect current session)
3. Review restore validation report: $REPORT_DIR/restore-validation-*.json
4. If issues, restore from pre-restore safety backup:
   \`\`\`bash
   tar -xzf $PRE_RESTORE_BACKUP -C /
   \`\`\`

---
*Generated by openclaw-security-container-rocky-v8.07*
EOF

echo ""
echo "============================================================="
echo " ✅ Restore Complete"
echo "============================================================="
echo " 📄 Report:   $REPORT_FILE"
echo " 📄 Log:      $RESTORE_LOG"
echo " 🛡️  Safety:  $PRE_RESTORE_BACKUP"
echo "============================================================="
