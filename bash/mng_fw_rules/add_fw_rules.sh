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

usage() {
  echo "Usage: $0 --ports <port-range> <ids_file> <ips_file> [rule_name_override]"
  echo ""
  echo "Arguments:"
  echo "  --ports <port-range>    Mandatory:  The port or port range (e.g., 443, 8080-8090)."
  echo "  --test                  Optional:   Run in test mode. Prints the salt command to stdout"
  echo "  <ids_file>              Mandatory:  Path to the file with the target salt IDs, one per line."
  echo "  <ips_file>              Mandatory:  Path to the file with the rule IP addresses, one per line."
  echo "  [rule_name_override]    Optional:   Override the rule name, which is otherwise derived"
  echo "                          from the <ips_file> filename."
  echo ""
  echo "Example (dynamic rule name):"
  echo "  $0 --ports 441-443 server_ids.txt Allow_MT5_AWS_APP.txt"
  echo ""
  echo "Example (override rule name):"
  echo "  $0 --ports 443 ids.txt ips.txt 'My Custom Rule'"
}

join_by_char() {
  local delimiter="$1"
  shift
  local result
  printf -v result "%s$delimiter" "$@"
  echo "${result%"$delimiter"}"
}

main() {
  # --- ARGS --- #
  local ports=""
  local test_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ports)
        if [[ -n "$2" ]]; then
          ports="$2"
          shift 2
        else
          log "$LINENO" "ERROR" "Argument for --ports is missing."
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
        break
        ;;
    esac
  done

  if [[ -z "$ports" ]]; then
    log "$LINENO" "ERROR" "The --ports argument is mandatory."
    usage
    return 1
  fi


  if [[ $# -lt 2 || $# -gt 3 ]]; then
    log "$LINENO" "ERROR" "Incorrect number of positional arguments provided."
    usage
    return 1
  fi

  local ids_file="$1"
  local ips_file="$2"
  local rule_name_override="${3:-}"

  if [[ ! -r "$ids_file" ]]; then
    log "$LINENO" "ERROR" "The specified ids file does not exist or is not readable: ${ids_file}"
    return 1
  fi

  if [[ ! -r "$ips_file" ]]; then
    log "$LINENO" "ERROR" "The specified ips file does not exist or is not readable: ${ips_file}"
    return 1
  fi

  # --- Rule Name --- #
  local rule_name
  if [[ -n "$rule_name_override" ]]; then
    rule_name="$rule_name_override"
    log "$LINENO" "INFO" "Using provided override for rule name: '${rule_name}'"
  else
    local filename
    filename=$(basename -- "$ips_file")
    rule_name="${filename%.*}"
    log "$LINENO" "INFO" "Derived rule name from filename: '${rule_name}'"
  fi


  # --- Read Files --- #
  log "$LINENO" "INFO" "Reading IDs from ${ids_file} and IPs from ${ips_file}"
  mapfile -t ids < "$ids_file"
  mapfile -t ips < "$ips_file"

  log "$LINENO" "INFO" "Starting firewall rule update process."

  local formatted_ids
  formatted_ids=$(join_by_char "," "${ids[@]}")
  log "$LINENO" "DEBUG" "Formatted IDS: ${formatted_ids}"

  local formatted_ips
  formatted_ips=$(join_by_char "," "${ips[@]}")
  log "$LINENO" "DEBUG" "Formatted IPS: ${formatted_ips}"

  log "$LINENO" "INFO" "Executing salt command..."

  # --- SALT Command --- #
  if [[ "$test_mode" == true ]]; then
    log "$LINENO" "INFO" "--- TEST MODE ENABLED ---"
    local simulated_command="salt -L \"$formatted_ids\" firewall.add_rule \"$rule_name\" \"$ports\" \"tcp\" \"allow\" \"in\" \"$formatted_ips\" --static -t 60"
    log "$LINENO" "INFO" "The following command would be executed:"
    echo "$simulated_command"
  else
    log "$LINENO" "INFO" "Executing salt command..."
    local salt_output
    if salt_output=$(salt -L "$formatted_ids" firewall.add_rule "$rule_name" "$ports" "tcp" "allow" "in" "$formatted_ips" --static -t 60 2>&1); then
      log "$LINENO" "INFO" "Salt command executed successfully."
      log "$LINENO" "DEBUG" "Salt output:\\n${salt_output}"
    else
      local exit_code=$?
      log "$LINENO" "ERROR" "Salt command failed with exit code: ${exit_code}."
      log "$LINENO" "ERROR" "Salt output:\\n${salt_output}"
      return "$exit_code"
    fi
  fi

  log "$LINENO" "INFO" "Firewall rule update completed."
}

main "$@"
