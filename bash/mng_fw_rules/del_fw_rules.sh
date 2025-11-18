#!/usr/bin/env bash

set -euo pipefail

readonly verbose=3


log() {
  if [[ $# -lt 3 ]]; then
    echo "FATAL: Log function requires a LINENO, LEVEL, and a MESSAGE." >&2
    return 1
  fi

  local line_num="$1"
  local level="${2^^}"
  local message="$3"
  local timestamp
  local level_num

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

  if [[ ${verbose:-0} -ge $level_num ]]; then
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    log_line=$(printf "%s [%s:%s] %s" "$timestamp" "$level" "$line_num" "$message")
    echo -e "$log_line" >&2
  fi
}

join_by_char() {
  local delimiter="$1"
  shift
  local result
  printf -v result "%s$delimiter" "$@"
  echo "${result%"$delimiter"}"
}

usage() {
  echo "Usage: $0 --rule-name <name> --ids-file <path> [--test]"
  echo ""
  echo "Arguments:"
  echo "  --rule-name <name>    Mandatory: The name of the firewall rule to delete."
  echo "  --ids-file <path>     Mandatory: Path to the file with server IDs, one per line."
  echo "  --test                Optional: Run in test mode. Prints the salt command to stdout"
  echo "                        instead of executing it."
  echo ""
  echo "Example (live run):"
  echo "  $0 --rule-name Allow_MT5_AWS_APP --ids-file server_ids.txt"
  echo ""
  echo "Example (test run):"
  echo "  $0 --rule-name Allow_MT5_AWS_APP --ids-file server_ids.txt --test"
}

main() {
  local rule_name=""
  local ids_file=""
  local test_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rule-name)
        if [[ -n "$2" ]]; then
          rule_name="$2"
          shift 2
        else
          log "$LINENO" "ERROR" "Argument for --rule-name is missing." >&2
          usage
          return 1
        fi
        ;;
      --ids-file)
        if [[ -n "$2" ]]; then
          ids_file="$2"
          shift 2
        else
          log "$LINENO" "ERROR" "Argument for --ids-file is missing." >&2
          usage
          return 1
        fi
        ;;
      --test)
        test_mode=true
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        log "$LINENO" "ERROR" "Unknown argument: $1" >&2
        usage
        return 1
        ;;
    esac
  done

  if [[ -z "$rule_name" || -z "$ids_file" ]]; then
    log "$LINENO" "ERROR" "Both --rule-name and --ids-file are mandatory arguments."
    usage
    return 1
  fi

  if [[ ! -r "$ids_file" ]]; then
    log "$LINENO" "ERROR" "The specified ids file is not readable: ${ids_file}"
    return 1
  fi


  log "$LINENO" "INFO" "Reading IDs from ${ids_file}"
  mapfile -t ids < "$ids_file"

  log "$LINENO" "INFO" "Starting firewall rule deletion process for rule: '${rule_name}'"

  local formatted_ids
  formatted_ids=$(join_by_char "," "${ids[@]}")
  log "$LINENO" "DEBUG" "Formatted IDS: ${formatted_ids}"

  if [[ "$test_mode" == true ]]; then
    log "$LINENO" "INFO" "--- TEST MODE ENABLED ---"
    local simulated_command="salt -L \"$formatted_ids\" firewall.delete_rule \"$rule_name\" dir=\"in\" --static -t 60"
    log "$LINENO" "INFO" "The following command would be executed:"
    echo "$simulated_command"
  else
    log "$LINENO" "INFO" "Executing salt command..."
    local salt_output
    if salt_output=$(salt -L "$formatted_ids" firewall.delete_rule "$rule_name" dir="in" --static -t 60 2>&1); then
      log "$LINENO" "INFO" "Salt command executed successfully."
      log "$LINENO" "DEBUG" "Salt output:\n${salt_output}"
    else
      local exit_code=$?
      log "$LINENO" "ERROR" "Salt command failed with exit code: ${exit_code}."
      log "$LINENO" "ERROR" "Salt output:\n${salt_output}"
      return "$exit_code"
    fi
  fi

  log "$LINENO" "INFO" "Firewall rule deletion completed."
}

main "$@"
