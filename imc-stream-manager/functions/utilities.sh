#!/bin/bash
set -eu

# Colors (fallback if no TTY)
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BLUE='\033[34m'
  C_YELLOW='\033[33m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_MAGENTA='\033[35m'
else
  C_RESET=''
  C_BLUE=''
  C_YELLOW=''
  C_RED=''
  C_GREEN=''
  C_MAGENTA=''
fi

log() {
  local lvl="$1"; shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local icon color
  case "$lvl" in
    INFO)    icon="ℹ️";  color="$C_BLUE" ;;
    WARN)    icon="⚠️";  color="$C_YELLOW" ;;
    ERROR)   icon="❌";  color="$C_RED" ;;
    SUCCESS) icon="✨";  color="$C_GREEN" ;;
    DEBUG)   icon="🐞";  color="$C_MAGENTA" ;;
    *)       icon="•";   color="$C_BLUE" ;;
  esac
  echo -e "${color}[$ts] $icon [$lvl] $*${C_RESET}" >&2
}

log_info() { log INFO "$*"; }
log_warn() { log WARN "$*"; }
log_error() { log ERROR "$*"; }
log_success() { log SUCCESS "$*"; }
log_debug() { [ "${DEBUG:-false}" = "true" ] && log DEBUG "$*" || true; }

need() { command -v "$1" >/dev/null 2>&1 || { log_error "Missing tool: $1"; exit 2; }; }

