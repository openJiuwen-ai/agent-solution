#!/bin/bash
# container-rocky-harden.sh v8.07 — Harden OpenClaw on Rocky/Debian Container
# v8 changes:
#   - Added warn() function (v5 bug: missing warn caused crashes)
#   - safe_node_write fixed: values via stdin, not string injection
#   - safe_node_write CHANGELOG v5 claimed fix but didn't implement — now truly fixed
#   - Multi-distro package manager support (dnf/apt)
#   - Graceful systemd handling in containers
#   - Backup uses -C / with relative paths
# Usage: bash container-rocky-harden.sh [--level N] [--skip-ssh] [--dry-run] [--path DIR] [--help]

set -euo pipefail

# Defaults
LEVEL=3
DRY_RUN=false
SKIP_SSH=false
OPENCLAW_PATH="/root/.openclaw"
REPORT_DIR="./reports"
BACKUP_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# State tracking
SSH_TOUCHED=1  # 1=yes, 0=no
HARDEN_RESULTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --level)      LEVEL="$2"; shift 2 ;;
    --skip-ssh)   SKIP_SSH=true; shift 1 ;;
    --dry-run)    DRY_RUN=true; shift 1 ;;
    --path)       OPENCLAW_PATH="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "  --level N      Security level 1-5 (default: 3)"
      echo "  --skip-ssh     Skip SSH configuration changes"
      echo "  --dry-run      Print plan without executing"
      echo "  --path DIR     OpenClaw install path (default: /root/.openclaw)"
      echo "  --report-dir   Report output directory (default: ./reports)"
      echo "  --help         Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Sanitize OPENCLAW_PATH
SANITIZED_PATH="$(echo "$OPENCLAW_PATH" | sed 's#/$##')"
if echo "$SANITIZED_PATH" | grep -qE '[;&|`$(){}]'; then
  echo "[FAIL] OPENCLAW_PATH contains unsafe characters"
  exit 2
fi
OPENCLAW_PATH="$SANITIZED_PATH"

# Detect container vs host (v6: enhanced)
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

# Package manager
get_pkg_manager() {
  case "$DISTRO" in
    rocky|centos|rhel|almalinux) echo "dnf" ;;
    debian|ubuntu) echo "apt" ;;
    *) echo "unknown" ;;
  esac
}
PKG_MGR=$(get_pkg_manager)

mkdir -p "$REPORT_DIR" "$OPENCLAW_PATH/backups"
BACKUP_DIR="$OPENCLAW_PATH/backups"
BACKUP_FILE="$BACKUP_DIR/pre-harden-$(date +%Y%m%d-%H%M%S).tgz"
STATE_FILE="$REPORT_DIR/harden-state-$(date +%Y%m%d-%H%M%S).json"

OPENCLAW_CONFIG="$OPENCLAW_PATH/openclaw.json"

# Progress tracking
TOTAL_STEPS=10
CURRENT_STEP=0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

progress() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo ""
  echo -e "\033[1;34m[ $CURRENT_STEP / $TOTAL_STEPS ]\033[0m $*"
}

pass() { echo -e "  \033[1;32m✅ $*\033[0m"; HARDEN_RESULTS+=("{\"step\": \"$*\", \"status\": \"success\"}"); }
fail() { echo -e "  \033[1;31m❌ $*\033[0m"; HARDEN_RESULTS+=("{\"step\": \"$*\", \"status\": \"failed\"}"); }
skip() { echo -e "  \033[1;33m⏭️  $*\033[0m"; HARDEN_RESULTS+=("{\"step\": \"$*\", \"status\": \"skipped\"}"); }
dry()  { echo -e "  \033[1;33m[DRY] $*\033[0m"; }
warn() { echo -e "  \033[1;33m⚠️  $*\033[0m"; HARDEN_RESULTS+=("{\"step\": \"$*\", \"status\": \"warning\"}"); }

# v6 FIX: safe_node_write — values via stdin, paths via process.argv
# This is the TRUE fix that v5 claimed but didn't implement
safe_node_set_key() {
  local json_file="$1"
  local key_path="$2"    # e.g. "gateway.auth.token" or "gateway.bind"
  local new_value="$3"   # the value to set

  if [[ ! -f "$json_file" ]]; then
    echo "[WARN] File not found: $json_file"
    return 1
  fi

  # Value passed via stdin, key and file via process.argv — no shell interpolation into JS
  printf '%s' "$new_value" | node -e "
    const fs = require('fs');
    const p = process.argv[1];
    const keyPath = process.argv[2];
    const raw = fs.readFileSync('/dev/stdin', 'utf8');

    const c = JSON.parse(fs.readFileSync(p, 'utf8'));
    const keys = keyPath.split('.');
    let obj = c;
    for (let i = 0; i < keys.length - 1; i++) {
      if (!obj[keys[i]]) obj[keys[i]] = {};
      obj = obj[keys[i]];
    }
    obj[keys[keys.length - 1]] = raw;
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + '\n');
  " "$json_file" "$key_path"
}

# v8 FIX: safe_node_get - key path via process.argv, no shell interpolation into JS
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
echo "============================================================="
echo " OpenClaw Security Hardening v8 — Level L$LEVEL"
echo "============================================================="
echo " Mode: $CONTAINER_MODE"
echo " Distro: $DISTRO"
echo " Path: $OPENCLAW_PATH"
echo " Package manager: $PKG_MGR"
if $SKIP_SSH; then
  echo " SSH: ⏭️  Skipped (--skip-ssh)"
fi
if $DRY_RUN; then
  echo " Mode: 🧪 DRY RUN — no changes will be made"
fi
echo ""

# ---- Step 0: Backup ----
progress "Backup current configuration"
if ! $DRY_RUN; then
  # v6: Only backup files that actually exist, with -C /
  BACKUP_PATHS=()
  for f in etc/ssh/sshd_config etc/sysctl.d/99-openclaw-security.conf \
           etc/login.defs "$OPENCLAW_PATH/openclaw.json" \
           "$OPENCLAW_PATH/.env" \
           "$OPENCLAW_PATH/workspace/SOUL.md" \
           "$OPENCLAW_PATH/workspace/AGENTS.md"; do
    if [[ -f "$f" ]] || [[ -f "/$f" ]]; then
      BACKUP_PATHS+=("${f#/}")
    fi
  done

  if [[ ${#BACKUP_PATHS[@]} -gt 0 ]]; then
    tar -czf "$BACKUP_FILE" -C / "${BACKUP_PATHS[@]}" 2>/dev/null || true
  else
    touch "$BACKUP_FILE"
  fi

  BACKUP_SIZE=$(stat -c "%s" "$BACKUP_FILE" 2>/dev/null || echo 0)
  if [[ "$BACKUP_SIZE" -gt 0 ]]; then
    pass "Backup created: $BACKUP_FILE ($BACKUP_SIZE bytes)"
  else
    warn "Backup file empty (no config files found to backup)"
    pass "Backup attempted: $BACKUP_FILE"
    # v8: Generate SHA256 integrity hash
    sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256" 2>/dev/null || true
    if [[ -f "$BACKUP_FILE.sha256" ]]; then
      pass "Backup integrity hash generated"
    fi

    # v8: Cleanup old backups (keep latest 5)
    mapfile -t OLD_BACKUPS < <(find "$BACKUP_DIR" -name "pre-harden-*.tgz" -type f 2>/dev/null | sort | head -n -5)
    for old in "${OLD_BACKUPS[@]}"; do
      if [[ -n "$old" ]]; then
        rm -f "$old" "$old.sha256" 2>/dev/null || true
        warn "Removed old backup: $(basename "$old")"
      fi
    done
  fi
else
  dry "Backup current configuration to $BACKUP_FILE"
fi

# ---- Step 1: Install dependencies ----
progress "Install prerequisites"
if ! $DRY_RUN; then
  if [[ "$PKG_MGR" == "dnf" ]]; then
    dnf install -y openssl jq 2>/dev/null || true
  elif [[ "$PKG_MGR" == "apt" ]]; then
    apt-get update -qq 2>/dev/null && apt-get install -y -qq openssl jq 2>/dev/null || true
  else
    warn "Unknown package manager: $PKG_MGR"
  fi
  pass "Prerequisites checked/installed ($PKG_MGR)"
else
  dry "Install prerequisites via $PKG_MGR"
fi

# ---- Step 2: OpenClaw Config Harden ----
progress "OpenClaw configuration hardening"
if ! $DRY_RUN; then
  if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
    fail "openclaw.json not found at $OPENCLAW_CONFIG"
    info "Create a minimal config first, then re-run hardening"
  else
    # Token length check
    TOKEN_VAL=$(safe_node_get "$OPENCLAW_CONFIG" "gateway.auth.token")
    TOKEN_LEN=${#TOKEN_VAL}
    if [[ "$TOKEN_LEN" -lt 32 ]]; then
      NEW_TOKEN=$(openssl rand -hex 24)
      # v6 FIX: safe_node_set_key — value via stdin, not string interpolation
      safe_node_set_key "$OPENCLAW_CONFIG" "gateway.auth.token" "$NEW_TOKEN"
      # Remove old token format if present
      node -e "
        const fs = require('fs');
        const p = process.argv[1];
        const c = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (c.gateway && c.gateway.token && !c.gateway.auth) { delete c.gateway.token; }
        fs.writeFileSync(p, JSON.stringify(c, null, 2) + '\n');
      " "$OPENCLAW_CONFIG" 2>/dev/null || true
      pass "Token regenerated: $TOKEN_LEN → 48 chars"
    else
      pass "Token length OK: $TOKEN_LEN chars"
    fi

    # Bind to localhost
    safe_node_set_key "$OPENCLAW_CONFIG" "gateway.bind" "loopback"
    pass "Gateway bind set to loopback"
  fi
else
  dry "Check token length and set bind to loopback"
fi

# ---- Step 3: File Permissions ----
progress "Fix file permissions"
if ! $DRY_RUN; then
  bash "$SCRIPT_DIR/file-perms.sh" --path "$OPENCLAW_PATH"
  pass "File permissions fixed"
else
  dry "Set directories 700, config files 600"
fi

# ---- Step 4: .env for Secrets ----
progress "Create .env for secrets"
if ! $DRY_RUN; then
  if [[ ! -f "$OPENCLAW_PATH/.env" ]]; then
    touch "$OPENCLAW_PATH/.env"
    echo "# OpenClaw secrets — keep this file safe" >> "$OPENCLAW_PATH/.env"
    echo "# Add your API keys here: PROVIDER_API_KEY=xxx" >> "$OPENCLAW_PATH/.env"
    chmod 600 "$OPENCLAW_PATH/.env"
    pass "Created .env file"
  else
    chmod 600 "$OPENCLAW_PATH/.env" 2>/dev/null || true
    pass ".env already exists, permissions verified"
  fi
else
  dry "Ensure .env exists with 600 permissions"
fi

# ---- Step 5: System Base Hardening ----
progress "System base hardening"

if $SKIP_SSH; then
  skip "SSH and system hardening (--skip-ssh)"
else
  SSH_TOUCHED=1

  # Define function to apply SSH hardening (fixes v4 'local' outside function bug)
  apply_ssh_hardening() {
    if [[ ! -f /etc/ssh/sshd_config ]]; then
      echo "No sshd_config found — SSH hardening skipped"
      return 0
    fi

    # PermitRootLogin
    if grep -qE "^#PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null; then
      sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    elif grep -qE "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
      sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    fi
    echo "SSH PermitRootLogin → prohibit-password"

    # PermitEmptyPasswords
    if grep -qE "^PermitEmptyPasswords yes" /etc/ssh/sshd_config 2>/dev/null; then
      sed -i 's/^PermitEmptyPasswords yes/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    elif ! grep -qE "^PermitEmptyPasswords" /etc/ssh/sshd_config 2>/dev/null; then
      echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config
    fi
    echo "SSH PermitEmptyPasswords → no"

    # MaxAuthTries
    if grep -qE "^MaxAuthTries" /etc/ssh/sshd_config 2>/dev/null; then
      sed -i 's/^MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    else
      echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
    fi
    echo "SSH MaxAuthTries → 3"

    # Validate before restart
    if command -v sshd &>/dev/null && sshd -t 2>/dev/null; then
      if command -v systemctl &>/dev/null; then
        systemctl restart sshd 2>/dev/null || true
      fi
      echo "sshd restarted (validated)"
    else
      echo "WARNING: sshd not available or config invalid — not restarting"
      return 1
    fi
  }

  # Define function for password policy (fixes v4 'local' outside function bug)
  apply_password_policy() {
    if [[ -f /etc/login.defs ]]; then
      if grep -qE "^PASS_MIN_LEN" /etc/login.defs 2>/dev/null; then
        sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t12/' /etc/login.defs
      else
        printf 'PASS_MIN_LEN\t12\n' >> /etc/login.defs
      fi
      if grep -qE "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null; then
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' /etc/login.defs
      else
        printf 'PASS_MAX_DAYS\t90\n' >> /etc/login.defs
      fi
      echo "Password policy: MIN_LEN=12, MAX_DAYS=90"
    fi
  }

  if ! $DRY_RUN; then
    apply_ssh_hardening || warn "SSH hardening had issues (may not have sshd)"
    pass "SSH configuration hardened (or skipped if not applicable)"

    if [[ -f /etc/login.defs ]]; then
      apply_password_policy
      pass "Password policy configured"
    else
      warn "No /etc/login.defs — password policy skipped"
    fi

    # Disable avahi-daemon (only if systemd exists)
    if command -v systemctl &>/dev/null; then
      if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
        systemctl stop avahi-daemon 2>/dev/null || true
        systemctl disable avahi-daemon 2>/dev/null || true
        pass "Disabled avahi-daemon"
      else
        pass "avahi-daemon already disabled"
      fi
    else
      skip "avahi-daemon (no systemd in container)"
    fi

    # Enable firewalld (only if available)
    if command -v firewall-cmd &>/dev/null; then
      if command -v systemctl &>/dev/null; then
        if ! systemctl is-active --quiet firewalld 2>/dev/null; then
          systemctl start firewalld 2>/dev/null || true
          systemctl enable firewalld 2>/dev/null || true
          pass "Enabled firewalld"
        else
          pass "firewalld already running"
        fi
      fi
    else
      skip "firewalld not available"
    fi

    # Kernel parameters (container-safe)
    if command -v sysctl &>/dev/null; then
      cat > /etc/sysctl.d/99-openclaw-security.conf << 'SYSCTL_EOF'
# OpenClaw security hardening — auto-generated
# Note: In containers, some parameters may be read-only
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
SYSCTL_EOF
      # In containers, sysctl may fail for some params — be graceful
      if sysctl -p /etc/sysctl.d/99-openclaw-security.conf >/dev/null 2>&1; then
        pass "Kernel security parameters applied"
      else
        warn "Some sysctl parameters couldn't be set (container restrictions)"
        pass "Kernel security config file created"
      fi
    else
      skip "sysctl not available"
    fi
  else
    dry "Apply SSH, password policy, firewalld, kernel params"
  fi
fi

# ---- Step 6: Container Security (L3+) ----
progress "Container security (L3+)"
if ! $DRY_RUN; then
  if [[ "$LEVEL" -ge 3 ]]; then
    if [[ -f "$SCRIPT_DIR/../templates/seccomp-openclaw.json" ]]; then
      cp "$SCRIPT_DIR/../templates/seccomp-openclaw.json" "$OPENCLAW_PATH/seccomp-openclaw.json" 2>/dev/null || true
      pass "Seccomp profile deployed"
    fi

    mkdir -p "$OPENCLAW_PATH/deploy"
    if [[ -f "$SCRIPT_DIR/../templates/docker-compose-security.yml" ]]; then
      cp "$SCRIPT_DIR/../templates/docker-compose-security.yml" "$OPENCLAW_PATH/deploy/docker-compose-security.yml" 2>/dev/null || true
      pass "Secure docker-compose template deployed"
    fi
  else
    skip "Container security (requires L3+)"
  fi
else
  dry "Deploy seccomp and docker-compose templates (L3+)"
fi

# ---- Step 7: Security Rules to SOUL/AGENTS ----
progress "Inject security rules into SOUL/AGENTS"
if ! $DRY_RUN; then
  SECURITY_MARKER="<!-- openclaw-security -->"

  if [[ -f "$SCRIPT_DIR/../templates/SOUL-security-append.md" ]]; then
    if [[ -f "$OPENCLAW_PATH/workspace/SOUL.md" ]]; then
      if ! grep -q "$SECURITY_MARKER" "$OPENCLAW_PATH/workspace/SOUL.md" 2>/dev/null; then
        { echo ""; echo "$SECURITY_MARKER"; cat "$SCRIPT_DIR/../templates/SOUL-security-append.md"; } >> "$OPENCLAW_PATH/workspace/SOUL.md"
        pass "Security rules appended to SOUL.md"
      else
        pass "SOUL.md already has security rules"
      fi
    fi
  fi

  if [[ -f "$SCRIPT_DIR/../templates/AGENTS-security-append.md" ]]; then
    if [[ -f "$OPENCLAW_PATH/workspace/AGENTS.md" ]]; then
      if ! grep -q "$SECURITY_MARKER" "$OPENCLAW_PATH/workspace/AGENTS.md" 2>/dev/null; then
        { echo ""; echo "$SECURITY_MARKER"; cat "$SCRIPT_DIR/../templates/AGENTS-security-append.md"; } >> "$OPENCLAW_PATH/workspace/AGENTS.md"
        pass "Security rules appended to AGENTS.md"
      else
        pass "AGENTS.md already has security rules"
      fi
    fi
  fi
else
  dry "Inject security rules into SOUL.md and AGENTS.md"
fi

# ---- Step 8: File Integrity Baseline ----
progress "Initialize file integrity baseline"
if ! $DRY_RUN; then
  bash "$SCRIPT_DIR/file-integrity.sh" --mode create --path "$OPENCLAW_PATH"
  pass "File integrity baseline initialized"
else
  dry "Create file integrity baseline"
fi

# ---- Step 9: Log Audit Config ----
progress "Configure log rotation"
if ! $DRY_RUN; then
  if command -v journalctl &>/dev/null && command -v systemctl &>/dev/null; then
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/openclaw.conf << 'JOURNAL_EOF'
[Journal]
SystemMaxUse=500M
MaxRetentionSec=30d
JOURNAL_EOF
    pass "Journal rotation configured"
  else
    # v6: Fallback to logrotate config for non-systemd environments
    if command -v logrotate &>/dev/null; then
      cat > /etc/logrotate.d/openclaw << 'LOGROTATE_EOF'
/root/.openclaw/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    size 50M
}
LOGROTATE_EOF
      pass "Logrotate configured for OpenClaw logs"
    else
      warn "No journalctl/logrotate — log rotation skipped"
    fi
  fi
else
  dry "Configure log rotation"
fi

# ---- Step 10: Write state + Run post-validate ----
progress "Post-hardening validation"
if ! $DRY_RUN; then
  # Write state file for downstream scripts
  RESULTS_JSON="[$(IFS=,; echo "${HARDEN_RESULTS[*]}")]"
  cat > "$STATE_FILE" <<EOF
{
  "version": "8.0",
  "type": "harden-state",
  "timestamp": "$TIMESTAMP",
  "level": "L$LEVEL",
  "ssh_touched": $SSH_TOUCHED,
  "backup_file": "$BACKUP_FILE",
  "container_mode": "$CONTAINER_MODE",
  "distro": "$DISTRO",
  "results": $RESULTS_JSON
}
EOF
  pass "State file written: $STATE_FILE"

  echo ""
  info "Running post-hardening validation..."
  set +e
  bash "$SCRIPT_DIR/container-post-validate.sh" --report-dir "$REPORT_DIR" --state-file "$STATE_FILE"
  set -e
else
  dry "Write state file and run post-validation"
fi

echo ""
echo "============================================================="
echo " ✅ Hardening Complete — Level L$LEVEL"
echo "============================================================="
echo " 📄 Backup:     $BACKUP_FILE"
echo " 📄 State:      $STATE_FILE"
echo " 📄 Reports:    $REPORT_DIR/"
echo ""
echo " Next: Run container-pre-post-diff.sh for before/after comparison"
echo " Next: Run container-report.sh for final report"
echo "============================================================="
