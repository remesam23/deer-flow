#!/bin/bash
# validate_config.sh - Validates configuration files and environment variables
# required for deer-flow to function correctly.
#
# Usage: ./validate_config.sh [--strict] [--env-file <path>]
#   --strict      Treat warnings as errors
#   --env-file    Path to .env file (default: .env in project root)

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
STRICT_MODE=false
ERRORS=0
WARNINGS=0

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT_MODE=true
      shift
      ;;
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; ((WARNINGS++)) || true; }
error() { echo "[ERROR] $*" >&2; ((ERRORS++)) || true; }

check_required_var() {
  local var_name="$1"
  local value="${!var_name:-}"
  if [[ -z "$value" ]]; then
    error "Required environment variable '${var_name}' is not set or empty."
  else
    info "${var_name} ... OK"
  fi
}

check_optional_var() {
  local var_name="$1"
  local default_hint="$2"
  local value="${!var_name:-}"
  if [[ -z "$value" ]]; then
    warn "Optional variable '${var_name}' is not set. Default: ${default_hint}"
  else
    info "${var_name} ... OK"
  fi
}

# ---------------------------------------------------------------------------
# Load .env if present
# ---------------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  info "Loading environment from: ${ENV_FILE}"
  # Export variables; skip comments and blank lines
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport
else
  warn ".env file not found at '${ENV_FILE}'. Checking system environment only."
fi

# ---------------------------------------------------------------------------
# Required variables
# ---------------------------------------------------------------------------
info "--- Checking required variables ---"
check_required_var "OPENAI_API_KEY"
check_required_var "TAVILY_API_KEY"

# ---------------------------------------------------------------------------
# Optional / recommended variables
# ---------------------------------------------------------------------------
info "--- Checking optional variables ---"
check_optional_var "OPENAI_BASE_URL"         "https://api.openai.com/v1"
check_optional_var "OPENAI_MODEL"            "gpt-4o"
check_optional_var "REASONING_MODEL"         "o1-mini"
check_optional_var "MAX_SEARCH_RESULTS"      "5"
check_optional_var "DEER_FLOW_ENV"           "development"
check_optional_var "LOG_LEVEL"               "INFO"

# ---------------------------------------------------------------------------
# Validate conf/config.yaml if it exists
# ---------------------------------------------------------------------------
CONFIG_YAML="${PROJECT_ROOT}/conf/config.yaml"
if [[ -f "$CONFIG_YAML" ]]; then
  info "--- Validating conf/config.yaml ---"
  if command -v python3 &>/dev/null; then
    python3 - <<'PYEOF'
import sys, yaml, pathlib
try:
    data = yaml.safe_load(pathlib.Path("${CONFIG_YAML}").read_text())
    if not isinstance(data, dict):
        print("[ERROR] config.yaml does not contain a top-level mapping.", file=sys.stderr)
        sys.exit(1)
    print("[INFO]  conf/config.yaml is valid YAML.")
except yaml.YAMLError as exc:
    print(f"[ERROR] config.yaml parse error: {exc}", file=sys.stderr)
    sys.exit(1)
PYEOF
    # Capture non-zero exit from python block
    if [[ $? -ne 0 ]]; then
      ((ERRORS++)) || true
    fi
  else
    warn "python3 not available; skipping YAML syntax check for config.yaml."
  fi
else
  warn "conf/config.yaml not found — skipping YAML validation."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Config Validation Summary"
echo "========================================"
echo " Errors   : ${ERRORS}"
echo " Warnings : ${WARNINGS}"
echo "========================================"

if [[ $ERRORS -gt 0 ]]; then
  echo "RESULT: FAILED (${ERRORS} error(s) found)" >&2
  exit 1
fi

if [[ $STRICT_MODE == true && $WARNINGS -gt 0 ]]; then
  echo "RESULT: FAILED in strict mode (${WARNINGS} warning(s) treated as errors)" >&2
  exit 1
fi

echo "RESULT: PASSED"
exit 0
