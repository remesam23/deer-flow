#!/usr/bin/env bash
# run_all_checks.sh — Orchestrates all smoke-test checks for deer-flow.
# Runs environment, Docker, deployment, and frontend checks in sequence,
# collects results, and prints a consolidated summary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}✔${RESET}  $*"; }
fail() { echo -e "  ${RED}✘${RESET}  $*"; }
info() { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }

# ── Argument parsing ─────────────────────────────────────────────────────────
MODE="local"          # local | docker | all
VERBOSE=false
STOP_ON_FAILURE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -m, --mode MODE        Check mode: local | docker | all  (default: local)
  -v, --verbose          Stream each sub-script's output instead of capturing it
  -x, --stop-on-failure  Abort the suite on the first failing check
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)            MODE="$2"; shift 2 ;;
    -v|--verbose)         VERBOSE=true; shift ;;
    -x|--stop-on-failure) STOP_ON_FAILURE=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ── Check registry ────────────────────────────────────────────────────────────
# Each entry: "label|script_path|applicable_modes"
# applicable_modes is a comma-separated list of modes that should run this check.
CHECKS=(
  "Local environment|${SCRIPT_DIR}/check_local_env.sh|local,all"
  "Docker environment|${SCRIPT_DIR}/check_docker.sh|docker,all"
  "Local deployment|${SCRIPT_DIR}/deploy_local.sh|local,all"
  "Docker deployment|${SCRIPT_DIR}/deploy_docker.sh|docker,all"
  "Frontend|${SCRIPT_DIR}/frontend_check.sh|local,docker,all"
)

# ── Result tracking ───────────────────────────────────────────────────────────
declare -a PASSED=()
declare -a FAILED=()
declare -a SKIPPED=()

run_check() {
  local label="$1"
  local script="$2"
  local modes="$3"

  # Skip if this check doesn't apply to the selected mode
  if [[ ",${modes}," != *",${MODE},"* ]]; then
    SKIPPED+=("$label")
    warn "Skipped : ${label}"
    return
  fi

  if [[ ! -x "$script" ]]; then
    fail "Script not executable or missing: ${script}"
    FAILED+=("$label")
    ${STOP_ON_FAILURE} && exit 1
    return
  fi

  info "Running : ${label}"
  local exit_code=0

  if ${VERBOSE}; then
    bash "$script" || exit_code=$?
  else
    local output
    output=$(bash "$script" 2>&1) || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      echo "$output"
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    pass "Passed  : ${label}"
    PASSED+=("$label")
  else
    fail "Failed  : ${label} (exit ${exit_code})"
    FAILED+=("$label")
    ${STOP_ON_FAILURE} && exit 1
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      deer-flow Smoke Test Suite          ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo -e "  Mode    : ${CYAN}${MODE}${RESET}"
echo -e "  Verbose : ${CYAN}${VERBOSE}${RESET}\n"

for entry in "${CHECKS[@]}"; do
  IFS='|' read -r label script modes <<< "$entry"
  run_check "$label" "$script" "$modes"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}── Summary ─────────────────────────────────${RESET}"
echo -e "  ${GREEN}Passed : ${#PASSED[@]}${RESET}"
echo -e "  ${RED}Failed : ${#FAILED[@]}${RESET}"
echo -e "  ${YELLOW}Skipped: ${#SKIPPED[@]}${RESET}\n"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo -e "${RED}${BOLD}Smoke test FAILED.${RESET} Failing checks:"
  for name in "${FAILED[@]}"; do
    echo -e "  ${RED}•${RESET} ${name}"
  done
  echo ""
  exit 1
else
  echo -e "${GREEN}${BOLD}All applicable checks passed.${RESET}\n"
  exit 0
fi
