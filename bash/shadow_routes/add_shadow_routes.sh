#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
readonly SCRIPT_NAME=""
SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/shadowroutes/add_shadow_routes.log"
readonly DEFAULT_GOOGLE_DIR="/path/to/dir"
readonly DEFAULT_OTRS_DIR="/path/to/dir"
readonly REQUIRED_COMMANDS=(dirname date grep find sed)
VERBOSE=0

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# HELP FUNCTIONS
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} <EMAIL ADDRESS(ES)> [OPTIONS]

Arguments:
  <EMAIL ADDRESS(ES)>   (Required) A single, comma-separated string of email
                        addresses to process.

Options:
  -h, --help            Display this help message and exit.
  -v, --verbose         Increase verbosity to 'INFO'.
  -vv                   Increase verbosity to 'DEBUG'.
  -s, --service NAME    Specify the Service for routing ["Google","OTRS"].
                        (Default: Google)
  -f, --force           Force remove a user from an old domain file if a
                        conflict is found.

Usage:
  ./${SCRIPT_NAME} "test@example.com"
  ./${SCRIPT_NAME} "test@example.com" -vv -s "OTRS" --force

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
    WARN) level_num=0 ;;
    INFO) level_num=1 ;;
    DEBUG) level_num=2 ;;
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
# CORE LOGIC FUNCTIONS
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

validate_email() {
  local email="$1"
  [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

get_otrs_domain_base() {
  local domain="$1"

  case "$domain" in
    hfgsltd.com)
      echo "hfgs"
      return 0
      ;;
    hfm.com)
      echo "hfm_com"
      return 0
      ;;
    mena.hfm.com)
      echo "mena"
      return 0
      ;;
  esac

  local working_domain="$domain"

  working_domain="${working_domain//.co./.}"
  working_domain="${working_domain//.com./.}"

  if [[ $working_domain == *.com ]]; then
    working_domain="${working_domain%.com}"
  fi

  local base="${working_domain//./_}"

  base="${base//-/}"

  echo "$base"
}

get_google_domain_base() {
  local domain="$1"
  local working_domain="$domain"

  working_domain="${working_domain//.co./.}"

  if [[ $working_domain == *.com ]]; then
    working_domain="${working_domain%.com}"
  fi

  local base="${working_domain//./_}"
  base="${base//-/_}"

  echo "$base"
}

# get_domain_base_from_domain() {
#   local domain="$1"
#   local working_domain="$domain"
#
#   working_domain="${working_domain//.co./.}"
#
#   if [[ $working_domain == *.com ]]; then
#     working_domain="${working_domain%.com}"
#   fi
#
#   local base="${working_domain//./_}"
#   base="${base//-/_}"
#
#   echo "$base"
# }

process_single_email() {
  local email="$1"
  local force="$2"
  local service_name="${3}"

  log "$LINENO" "INFO" "Processing email: ${email}"
  if ! validate_email "$email"; then
    log "$LINENO" "ERROR" "Invalid email format: '$email'"
    return 1
  fi

  local email_user="${email%@*}"
  local email_domain="${email#*@}"
  log "$LINENO" "DEBUG" "Extracted user='${email_user}', domain='${email_domain}'"

  local domain_base=""
  local output_dir=""
  local shadow_route_file=""

  case "${service_name^^}" in
    GOOGLE)
      domain_base=$(get_google_domain_base "$email_domain")
      log "$LINENO" "DEBUG" "Derived domain base: '${domain_base}'"
      output_dir="${DEFAULT_GOOGLE_DIR}"
      shadow_route_file="${output_dir}/shadow_route_zcs_google_${domain_base}"
      ;;
    OTRS)
      domain_base=$(get_otrs_domain_base "$email_domain")
      log "$LINENO" "DEBUG" "Derived domain base: '${domain_base}'"
      output_dir="${DEFAULT_OTRS_DIR}"
      shadow_route_file="${output_dir}/shadow_route_otrs_${domain_base}"
      ;;
    *)
      log "$LINENO" "ERROR" "Invalid service specified: '${service_name}'"
      return 1
      ;;
  esac
  log "$LINENO" "DEBUG" "Service '${service_name}' mapped to file: '${shadow_route_file}'"

  if [[ ! -f $shadow_route_file ]]; then
    log "$LINENO" "ERROR" "Shadow route file does not exist: $shadow_route_file"
    return 1
  fi

  if grep -qriE "^${email_user}$" "$output_dir"; then
    log "$LINENO" "WARN" "User '${email_user}' already exists in a shadow file."
    if [[ $force == true ]]; then
      log "$LINENO" "INFO" "Force mode enabled. Removing user from all existing files..."
      find "$output_dir" -type f -name 'shadow_route*' -exec sed -i "/^${email_user}$/d" {} +
    else
      log "$LINENO" "ERROR" "User conflict for '${email_user}'. Use --force to override."
      return 1
    fi
  fi

  if ! echo "$email_user" >>"$shadow_route_file"; then
    log "$LINENO" "ERROR" "Failed to write to shadow file. Check permissions for: $shadow_route_file"
    return 1
  fi

  log "$LINENO" "INFO" "Successfully added '${email_user}' to ${shadow_route_file}"
  return 0
}

main() {
  local force=false
  local -a positional_args=()
  check_filepath "$LOG_FILE"

  # --- ARGUMENT PARSING ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v | --verbose)
        ((VERBOSE++))
        shift
        ;;
      -vv)
        ((VERBOSE += 2))
        shift
        ;;
      -s | --service)
        if [[ -z ${2-} ]]; then
          echo "ERROR: The --output flag requires a <service name> argument." >&2
          usage >&2
          exit 1
        fi
        service_name="$2"
        shift 2
        ;;
      -f | --force)
        force=true
        shift
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

  log "$LINENO" "INFO" "Script starting..."
  log "$LINENO" "DEBUG" "Verbosity set to: ${VERBOSE}"
  check_dependencies

  # --- VALIDATION ---
  if [[ ${#positional_args[@]} -ne 1 ]]; then
    log "$LINENO" "ERROR" "This script requires one argument: a comma-separated list of emails."
    usage >&2
    exit 1
  fi

  local all_emails_str="${positional_args[0]}"
  all_emails_str="${all_emails_str//[[:space:]]/}"
  log "$LINENO" "DEBUG" "Positional Argument: ${all_emails_str}"
  log "$LINENO" "DEBUG" "Output Directory: ${service_name}"

  # -- MAIN LOOP ---
  local -a valid_emails=()
  local -a invalid_emails=()

  while IFS= read -r email; do
    [[ -z $email ]] && continue

    if process_single_email "$email" "$force" "$service_name"; then
      valid_emails+=("$email")
    else
      invalid_emails+=("$email")
    fi
  done <<<"${all_emails_str//,/$'\n'}"

  # --- REPORT ---
  log "$LINENO" "INFO" "Processing complete."
  log "$LINENO" "INFO" "Successfully processed: ${#valid_emails[@]} email(s)."
  log "$LINENO" "INFO" "Failed to process: ${#invalid_emails[@]} email(s)."

  if [[ ${#invalid_emails[@]} -gt 0 ]]; then
    log "$LINENO" "ERROR" "Failures occurred for the following emails: ${invalid_emails[*]}"
    exit 1
  fi

  log "$LINENO" "INFO" "Script finished successfully."
}

main "$@"
