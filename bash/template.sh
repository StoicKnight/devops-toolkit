#!/usr/bin/env bash

# FIX: adapt the template to the scope

set -o errexit -o nounset -o pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/path/to/log_file.log" #NOTE: Set the file path for logs
readonly REQUIRED_COMMANDS=(dirname date) #NOTE: Add any required commands to this array.
VERBOSE=0

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# HELP FUNCTIONS
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#NOTE: Change the output to the usage of the script
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} <POSITIONAL ARGUMENT> [OPTIONS]

Arguments:
  <POSITIONAL ARGUMENT> (Required)

Options:
  -h, --help            Display this help message.
  -v, --verbose         Increase versbosity. Can be used multiple times.
  -o, --output DIR      Specify the output directory.

Usage:
  ./${SCRIPT_NAME} "argument"
  ./${SCRIPT_NAME} "argument" --verbose
  ./${SCRIPT_NAME} "argument" -o "/path/to/dir" -vv

EOF
}

log() {
  if [[ $# -lt 3 ]]; then
    echo "FATAL: Log function requires a LINENO, LEVEL and a MESSAGE." >&2
    return 1
  fi

  local line_num="$1"
  local level="${2}"
  local message="$3"
  local timestamp level_num log_line

  level="${level^^}"

  case "$level" in
    ERROR) level_num=0 ;;
    WARN) level_num=1 ;;
    INFO) level_num=2 ;;
    DEBUG) level_num=3 ;;
    *)
      echo "FATAL: Invalid log level '$level' used in script." >&2
      return 1
      ;;
  esac

  if [[ ${VERBOSE:-0} -ge $level_num ]]; then
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    log_line=$(printf "%s [%s:%s] %s" "$timestamp" "$level" "$line_num" "$message")
    echo "$log_line" >&2

    if [[ -n ${LOG_FILE-} ]]; then
      echo "$log_line" >>"$LOG_FILE"
    fi
  fi
}

check_filepath() {
  local file_path="$1"
  log "$LINENO" "DEBUG" "Checking for file at: ${file_path}"

  if [[ ! -f $file_path ]]; then
    log "$LINENO" "INFO" "File does not exist. Create file '${file_path}'..."
    local dir_path
    dir_path=$(dirname "$file_path")

    if ! mkdir -p "$dir_path"; then
      log "$LINENO" "ERROR" "Failed to create directory path: ${dir_path}"
      exit 1
    fi

    if ! touch "$file_path"; then
      log "$LINENO" "ERROR" "Failed to create file, check permissions: ${file_path}" >&2
      exit 1
    fi

    log "$LINENO" "INFO" "Successfully created file: ${file_path}"
  fi

  if ! [[ -w $file_path ]]; then
    log "$LINENO" "ERROR" "File is not writable: ${file_path}" >&2
    exit 1
  fi

  log "$LINENO" "DEBUG" "File is ready and writable."
}

check_dependencies() {
  local missing_deps=0
  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "FATAL: Required command '${cmd}' is not installed or not in PATH." >&2
      missing_deps=1
    fi
  done
  if [[ $missing_deps -eq 1 ]]; then
    exit 1
  fi
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# MAIN FUNCTION
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
main() {
  local output_dir=""
  local -a positional_args=()

  check_filepath "$LOG_FILE"

  # --- ARGUMENT PARSING ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v | --verbose)
        ((VERBOSE++))
        shift
        ;;
      -o | --output)
        if [[ -z ${2-} ]]; then
          echo "ERROR: The --output flag requires a directory path argument." >&2
          usage >&2
          exit 1
        fi
        output_dir="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        echo "ERROR: Unknown option '$1'" >&2
        usage >&2
        exit 1
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  # --- VALIDATION ---
  if [[ ${#positional_args[@]} -ne 1 ]]; then #NOTE: Set the correct number of positional arguments
    log "$LINENO" "ERROR" "Incorrect number of arguments." >&2
    usage >&2
    exit 1
  fi

  local my_argument="${positional_args[0]}" #NOTE: add the correct arguments

  # --- SCRIPT MAIN LOGIC ---
  log "$LINENO" "INFO" "Script starting..."
  check_dependencies
  log "$LINENO" "DEBUG" "Positional Argument: ${my_argument}" #NOTE: add all positional arguments
  log "$LINENO" "DEBUG" "Output Directory: ${output_dir:-'Not provided'}"
  log "$LINENO" "INFO" "Script finished successfully."
}

main "$@"
