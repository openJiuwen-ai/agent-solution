#!/bin/bash
# rocky-prereq-check.sh v8.07 — Check prerequisites for OpenClaw hardening
# v8.07 fixes:
#   - Multi-distro support: Rocky, Debian, Ubuntu
#   - Graceful handling of missing optional tools
#   - Better container detection (dockerenv, cgroup, podman)
# Usage: bash rocky-prereq-check.sh [--json]

set -euo pipefail

OUTPUT_JSON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_JSON=true; shift ;;
    --help)
      echo "Usage: $0 [--json]"
      echo "  --json    Output in JSON format"
      echo "  --help    Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Detect container vs host (v6: enhanced detection)
detect_container_mode() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || \
     grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    echo "container"
  else
    echo "host"
  fi
}

# Detect Linux distribution
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  elif [[ -f /etc/redhat-release ]]; then
    echo "rocky"
  else
    echo "unknown"
  fi
}

CONTAINER_MODE=$(detect_container_mode)
DISTRO=$(detect_distro)

# Logging functions
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
pass()  { echo -e "\033[1;32m[PASS]\033[0m $*"; }
fail()  { echo -e "\033[1;31m[FAIL]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# Gather data
IS_ROOT=false
HAS_NODE=false
HAS_BASH=false
HAS_OPENSSL=false
HAS_JQ=false
HAS_SYSCTL=false
HAS_SS=false
HAS_NETSTAT=false
HAS_APT=false
HAS_DNF=false
HAS_PODMAN=false
HAS_DOCKER=false
DISK_OK=false
ISSUES=()
WARNINGS=()

# Root check
if [[ $EUID -eq 0 ]]; then
  IS_ROOT=true
fi

# Distro check
case "$DISTRO" in
  rocky|centos|rhel|almalinux)
    pass "Linux distro: $DISTRO (RHEL family)"
    HAS_DNF=$(command -v dnf &>/dev/null && echo true || echo false)
    ;;
  debian|ubuntu)
    pass "Linux distro: $DISTRO (Debian family)"
    HAS_APT=$(command -v apt-get &>/dev/null && echo true || echo false)
    ;;
  alpine)
    warn "Linux distro: $DISTRO (Alpine — limited compatibility)"
    ;;
  *)
    fail "Unknown distro: $DISTRO"
    ISSUES+=("Unknown OS distribution")
    ;;
esac

# Essential commands
command -v node &>/dev/null && HAS_NODE=true || { HAS_NODE=false; ISSUES+=("node is required"); }
command -v bash &>/dev/null && HAS_BASH=true || { HAS_BASH=false; ISSUES+=("bash is required"); }
command -v openssl &>/dev/null && HAS_OPENSSL=true || { HAS_OPENSSL=false; ISSUES+=("openssl is required"); }
command -v jq &>/dev/null && HAS_JQ=true || { HAS_JQ=false; WARNINGS+=("jq is recommended for JSON processing"); }
command -v sysctl &>/dev/null && HAS_SYSCTL=true
command -v ss &>/dev/null && HAS_SS=true
command -v netstat &>/dev/null && HAS_NETSTAT=true
command -v podman &>/dev/null && HAS_PODMAN=true
command -v docker &>/dev/null && HAS_DOCKER=true

# Disk space (need at least 50MB for reports + backups)
DISK_AVAIL=$(df -BM / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'M' || echo "0")
if [[ "$DISK_AVAIL" -ge 50 ]]; then
  DISK_OK=true
fi

if $OUTPUT_JSON; then
  cat <<EOF
{
  "status": "prereq_check",
  "distro": "$DISTRO",
  "container_mode": "$CONTAINER_MODE",
  "is_root": $IS_ROOT,
  "has_node": $HAS_NODE,
  "has_bash": $HAS_BASH,
  "has_openssl": $HAS_OPENSSL,
  "has_jq": $HAS_JQ,
  "has_sysctl": $HAS_SYSCTL,
  "has_ss": $HAS_SS,
  "has_netstat": $HAS_NETSTAT,
  "has_podman": $HAS_PODMAN,
  "has_docker": $HAS_DOCKER,
  "disk_available_mb": $DISK_AVAIL,
  "disk_ok": $DISK_OK,
  "issues": [$(printf '"%s",' "${ISSUES[@]}" 2>/dev/null | sed 's/,$//')],
  "warnings": [$(printf '"%s",' "${WARNINGS[@]}" 2>/dev/null | sed 's/,$//')]
}
EOF
  exit 0
fi

# Human-readable output
echo "============================================================="
echo " OpenClaw Security Hardening — Pre-flight Check v8"
echo "============================================================="
echo ""

# 1. Distro Check
if [[ "$DISTRO" == "unknown" ]]; then
  fail "Unknown OS distribution"
  exit 1
else
  pass "Linux distro: $DISTRO"
fi

# 2. Container mode
info "Container mode: $CONTAINER_MODE"

# 3. Root check
if $IS_ROOT; then
  pass "Running as root"
else
  warn "Not running as root — some operations may require elevated privileges"
fi

# 4. Disk space
if $DISK_OK; then
  pass "Disk space OK: ${DISK_AVAIL}MB available"
else
  fail "Low disk space: ${DISK_AVAIL}MB (need ≥50MB)"
fi

# 5. Essential tools
info "Checking essential tools..."
CHECK_FAIL=0
CHECK_WARN=0

check_required() {
  local name="$1"
  if command -v "$1" &>/dev/null; then
    pass "$name is available"
  else
    fail "$name is missing (required)"
    CHECK_FAIL=$((CHECK_FAIL + 1))
  fi
}

check_optional() {
  local name="$1"
  if command -v "$1" &>/dev/null; then
    pass "$name is available"
  else
    warn "$name is not available (optional)"
    CHECK_WARN=$((CHECK_WARN + 1))
  fi
}

check_required "bash"
check_required "node"
check_required "openssl"
check_optional "jq"
check_optional "sysctl"
check_optional "ss"
check_optional "netstat"

echo ""
if [[ $CHECK_FAIL -eq 0 ]]; then
  pass "All required tools are available"
else
  fail "$CHECK_FAIL required tool(s) missing, cannot continue"
  exit 1
fi

if [[ $CHECK_WARN -gt 0 ]]; then
  info "$CHECK_WARN optional tool(s) not found — reduced functionality"
fi

# 6. Container environment warnings
if [[ "$CONTAINER_MODE" == "container" ]]; then
  echo ""
  info "Container environment detected:"
  if ! command -v systemctl &>/dev/null; then
    info "  • No systemd — service management operations will be skipped"
  fi
  if [[ ! -d /etc/ssh ]]; then
    info "  • No SSH server — SSH hardening will be skipped"
  fi
  info "  • Container-level only: file permissions, token rotation, config hardening"
fi

echo ""
echo "============================================================="
echo " ✅ Pre-flight check passed"
echo "============================================================="
