#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
readonly SCRIPT_NAME="$(basename "$0")"

# ---  Help functions ---
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} <SALT_TARGET> <USERNAME> [OPTIONS]

Arguments:
  <SALT_TARGET>   (Required) The Salt compound target string (e.g., "G@os:windows").
                  Must be quoted if it contains spaces or special characters.
  <USERNAME>      (Required) The local user to search for on the minions.

Options:
  --delete        Delete the user from the minions where it is found.
  --disable       Disable the user on the minions where it is found.
                  Cannot be used with --delete.

  -o, --output    Path to a file where the CSV result will be saved.
  -h, --help      Display this help and exit.

Usage:
  ./find_minions_by_user.sh "G@os:Debian" jdoe
  ./find_minions_by_user.sh "L@minion1,minion2" root -o /tmp/root_hosts.csv

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
  # ISO format
  # timestamp=$(date -u --iso-8601=seconds)

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

# --- Main Function ---
main() {
  local salt_target=""
  local target_user=""
  local output_file=""
  local delete_user=false
  local disable_user=false
  local -a positional_args=()

  check_dependencies # Check for dependencies

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
      --delete)
        delete_user=true
        shift
        ;;
      --disable)
        disable_user=true
        shift
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
  if [[ ${#positional_args[@]} -ne 2 ]]; then
    log "ERROR" "Incorrect number of arguments. Both <SALT_TARGET> and <USERNAME> are required." >&2
    usage >&2
    exit 1
  fi

  if [[ $delete_user == true && $disable_user == true ]]; then
    log "ERROR" "The --delete and --disable flags cannot be used at the same time." >&2
    usage >&2
    exit 1
  fi

  salt_target="${positional_args[0]}"
  target_user="${positional_args[1]}"

  # --- Windows Target Check ---
  local is_windows=false
  if [[ $salt_target == *"os:windows"* ]]; then
    is_windows=true
  fi

  # --- Salt Command ---
  log "INFO" "Querying Salt minions with target '${salt_target}' for user '${target_user}'..."
  local -a find_cmd_array=(
    salt
    --static
    -t 60
    -C "$salt_target"
    user.list_users
    --out=json
    --out-indent=-1
  )

  local salt_output
  if ! salt_output=$("${find_cmd_array[@]}"); then
    log "ERROR" "The Salt command to find minions with specified user failed. Exit code: $?." >&2
    exit 1
  fi

  # --- JSON parsing ---
  local minion_list_csv
  minion_list_csv=$(
    echo "$salt_output" |
      sed -n '/^{/,$p' |
      jq -r --arg user "$target_user" \
        '[ to_entries[] | select(.value | index($user)) | .key ] | join(",")'
  )

  # --- Results ---
  if [[ -z $minion_list_csv ]]; then
    log "INFO" "Command successful, but no minions were found with user '${target_user}'."
  else
    log "SUCCESS" "Found minions with user '${target_user}'."

    # --- Output to file ---
    if [[ -n $output_file ]]; then
      log "INFO" "Exporting result to '${output_file}'..."
      # Check if the directory is writable
      local output_dir
      output_dir=$(dirname "$output_file")
      if ! [[ -d $output_dir && -w $output_dir ]]; then
        log "ERROR" "Directory '${output_dir}' does not exist or is not writable." >&2
        exit 1
      fi
      echo "$minion_list_csv" | tr ',' '\n' >"$output_file"
      log "INFO" "Successfully exported to '${output_file}'."
    fi

    # --- Delete User ---
    if [[ $delete_user == true ]]; then
      log "INFO" "Preparing to DELETE user '${target_user}' on found minions..."
      local -a delete_cmd_array
      if [[ $is_windows == true ]]; then
        delete_cmd_array=(salt -t 60 -L "$minion_list_csv" user.delete "$target_user" purge=true force=true)
      else
        delete_cmd_array=(salt -t 60 -L "$minion_list_csv" user.delete "$target_user" remove=true force=true)
      fi
      log "INFO" "Executing: ${delete_cmd_array[*]}"
      "${delete_cmd_array[@]}"

      # --- Disable User ---
    elif [[ $disable_user == true ]]; then
      log "INFO" "Preparing to DISABLE user '${target_user}' on found minions..."
      local -a disable_cmd_array
      if [[ $is_windows == true ]]; then
        disable_cmd_array=(salt -t 60 -L "$minion_list_csv" user.update "$target_user" account_disabled=True)
      else
        disable_cmd_array=(salt -t 60 -L "$minion_list_csv" user.chshell "$target_user" /usr/sbin/nologin)
      fi
      log "INFO" "ACTION: Executing: ${disable_cmd_array[*]}"
      "${disable_cmd_array[@]}"
    fi
  fi

  # STDOUT
  echo
  log "INFO" "Found Minions:"
  echo
  echo "---------------------------"
  echo "$minion_list_csv" | tr ',' '\n'
  echo "---------------------------"
}

# --- Main Function Call ---
main "$@"
