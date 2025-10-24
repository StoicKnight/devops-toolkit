#!/usr/bin/env bash

set -euo pipefail

readonly verbose=3
readonly rule_name="Allow_AWS_APP"
readonly ports="443"

readonly ips=(
  "10.20.68.132" "10.20.69.46" "10.20.69.232" "10.20.69.242"
  "10.20.68.108" "10.20.68.45" "10.20.5.137" "10.20.5.111"
  "10.20.5.7" "10.20.5.119" "10.20.4.78" "10.20.5.105"
)

readonly ids=(
  "tel111a.hfmarkets.com" "tel247a.hfmarkets.com" "tel248a.hfmarkets.com"
  "tel134.hfmarkets.com" "ha230a.hfmarkets.com" "tel234a.hfmarkets.com"
  "ha133.hfmarkets.com" "ha135.hfmarkets.com" "ha152.hfmarkets.com"
  "ha187.hfmarkets.com" "ha108.hfmarkets.com" "ha188a.hfmarkets.com"
  "tel250.hfmarkets.com" "ha97a.hfmarkets.com" "ha234a.hfmarkets.com"
  "ha231a.hfmarkets.com" "ha249.hfmarkets.com" "ha139a.hfmarkets.com"
  "ha170a.hfmarkets.com" "ha144.hfmarkets.com" "ha228.hfmarkets.com"
  "ha63a.hfmarkets.com" "ha160.hfmarkets.com" "tel95.hfmarkets.com"
  "ha204a.hfmarkets.com" "ha145.hfmarkets.com" "tel55.hfmarkets.com"
  "tel205a.hfmarkets.com" "tel148.hfmarkets.com" "tel128.hfmarkets.com"
)

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
    echo "$log_line" >&2
  fi
}

join_by_char() {
  local delimiter="$1"
  shift
  local result
  printf -v result "%s$delimiter" "$@"
  echo "${result%"$delimiter"}"
}

main() {
  log "$LINENO" "INFO" "Starting firewall rule update process."

  local formatted_ids
  formatted_ids=$(join_by_char "," "${ids[@]}")
  log "$LINENO" "DEBUG" "Formatted IDS: ${formatted_ids}"

  local formatted_ips
  formatted_ips=$(join_by_char "," "${ips[@]}")
  log "$LINENO" "DEBUG" "Formatted IPS: ${formatted_ips}"

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

  log "$LINENO" "INFO" "Firewall rule update completed."
}

main "$@"
