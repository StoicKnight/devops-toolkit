#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
readonly SCRIPT_NAME="$(basename "$0")"

# Help functions
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} <SALT_TARGET>

Arguments:
  <SALT_TARGET>   (Required) The Salt compound target string (e.g., "G@os:windows").
                             Must be quoted if it contains spaces or special characters.
Options:
  -o, --output    Path to a file where the CSV result will be saved.
  -h, --help      Display this help and exit.

Usage:
  ./${SCRIPT_NAME} "G@os:Debian" 
  ./${SCRIPT_NAME} "L@minion1,minion2"

EOF
}

log() {
  if [[ $# -lt 2 ]]; then
    log "ERROR" "Log function requires a LEVEL and a MESSAGE." >&2
    return 1
  fi
  local level timestamp message
  level="${1^^}"
  shift
  message="$*"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf "%s [%s] %s\n" "$timestamp" "$level" "$message"
}

check_dependencies() {
  local missing_deps=0
  for cmd in salt jq; do
    if ! command -v "$cmd" &>/dev/null; then
      log "ERROR" "Required command '${cmd}' is not installed or not in your PATH." >&2
      missing_deps=1
    fi
  done
  if [[ $missing_deps -eq 1 ]]; then
    exit 1
  fi
}

# Main Function
main() {
  local salt_target=""
  local state_script="update_minion_version"
  local output_file="update_minion_version.json"
  local -a positional_args=()

  check_dependencies

  # --- Argument Parsing ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o | --output)
        if [[ -z ${2-} ]]; then
          log "ERROR" "--output flag requires a file path argument." >&2
          usage >&2
          exit 1
        fi
        output_file="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        log "ERROR" "Unknown option '$1'" >&2
        usage >&2
        exit 1
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  # --- Argument Validation ---
  if [[ ${#positional_args[@]} -ne 1 ]]; then
    log "ERROR" "Incorrect number of arguments. <SALT_TARGET> is required." >&2
    usage >&2
    exit 1
  fi

  salt_target="${positional_args[0]}"

  # --- Salt Command ---
  log "INFO" "Apply Salt state '${state_script}' to target '${salt_target}'..."
  local -a cmd_array=(
    salt
    --static
    -t 60
    -C "$salt_target"
    state.apply
    "$state_script"
    saltenv=infra
    --out=json
    --out-indent=-1
  )

  local salt_output
  if ! salt_output=$("${cmd_array[@]}"); then
    log "ERROR" "The Salt command to apply state for salt service version upgrade failed. Exit code: $?." >&2
    exit 1
  fi

  echo "$salt_output" >>"$output_file"
}

# --- Main Function Call ---
main "$@"
