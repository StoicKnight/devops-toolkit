#!/usr/bin/env bash

set -euo pipefail

# --- Config ---
readonly SCRIPT_NAME="$(basename "${0}")"
readonly DEFAULT_DKIM_DIR="/etc/exim4/dkim"
readonly EXIM_USER="Debian-exim"
readonly EXIM_GROUP="Debian-exim"
readonly KEY_BITS="2048"

# --- Help Functions ---
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} [OPTIONS] <domains_source>

Generates DKIM RSA key pairs for a list of domains.

The <domains_source> argument is required and can be one of:
  - A path to a file containing one domain per line.
  - A comma-separated string of domains (e.g., "example.com,example.org").

Options:
  -o, --output DIR   Specify the output directory for the key pairs.
                     (Default: ${DEFAULT_DKIM_DIR})
  -b, --bits BITS    Specify the key length in bits.
                     (Default: 2048)
  -h, --help         Display this help message and exit.

EOF
}

log() {
  local level="${1^^}"
  local message="${2}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf "%s [%s] %s\n" "${timestamp}" "${level}" "${message}"
}

check_dependencies() {
  if ! command -v openssl &>/dev/null; then
    log "ERROR" "Required command 'openssl' is not installed or not in your PATH." >&2
    exit 1
  fi
}

gen_key_pair() {
  local domain="$1"
  local output_dir="$2"
  local key_bits="$3"
  local private_key_path="${output_dir}/${domain}.priv.key"
  local public_key_path="${output_dir}/${domain}.pub.pem"

  log "INFO" "Processing domain: ${domain}"

  if [[ -f $private_key_path ]]; then
    log "WARNING" "Skipping '${domain}': Private key already exists at ${private_key_path}"
    return 0
  fi

  log "INFO" "Generating ${key_bits}-bit RSA private key for ${domain}..."
  if ! openssl genrsa -out "${private_key_path}" "${key_bits}" &>/dev/null; then
    log "ERROR" "Failed to generate private key for ${domain}"
    return 1
  fi

  log "INFO" "Extracting public key for ${domain}..."
  if ! openssl rsa -in "$private_key_path" -pubout -out "$public_key_path" &>/dev/null; then
    log "ERROR" "Failed to extract public key for ${domain}. Cleaning up private key."
    rm "$private_key_path"
    return 1
  fi

  log "INFO" "Setting ownership and permissions for private key..."
  if ! chown "${EXIM_USER}:${EXIM_GROUP}" "$private_key_path" 2>/dev/null; then
    log "WARNING" "Could not set owner to '${EXIM_USER}:${EXIM_GROUP}'. User/group may not exist."
  fi
  chmod 640 "$private_key_path"

  log "INFO" "Successfully created keys for ${domain}."
  return 0
}

main() {
  local output_dir="${DEFAULT_DKIM_DIR}"
  local key_bits="${KEY_BITS}"
  local domains_source=""

  # --- Argument Parsing ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o | --output)
        if [[ -z ${2-} ]]; then
          log "ERROR" "The --output flag requires a directory path argument." >&2
          usage >&2
          exit 1
        fi
        output_dir="$2"
        shift 2
        ;;
      -b | --bits)
        if [[ -z ${2-} ]]; then
          log "ERROR" "The --bits flag requires a numeric argument." >&2
          usage >&2
          exit 1
        fi
        key_bits="$2"
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
        if [[ -n ${domains_source} ]]; then
          log "ERROR" "Too many arguments. Only one <domains_source> is allowed." >&2
          usage >&2
          exit 1
        fi
        domains_source="$1"
        shift
        ;;
    esac
  done

  # --- Initial Validation ---
  if [[ -z ${domains_source} ]]; then
    log "ERROR" "Missing required <domains_source> argument." >&2
    usage >&2
    exit 1
  fi

  # --- Check sudo elevation ---
  if [[ ${output_dir} == /etc* && ${EUID} -ne 0 ]]; then
    log "ERROR" "Writing to '${output_dir}' requires root privileges. Please run with sudo." >&2
    exit 1
  fi

  check_dependencies

  # --- Prepare Output Directory ---
  log "INFO" "Using output directory: ${output_dir}"
  if ! mkdir -p "$output_dir"; then
    log "ERROR" "Failed to create output directory: ${output_dir}" >&2
    exit 1
  fi
  if ! [[ -w $output_dir ]]; then
    log "ERROR" "Output directory is not writable: ${output_dir}" >&2
    exit 1
  fi

  # --- Prepare Domain List ---
  local -a domains=()
  if [[ -f ${domains_source} && -r $domains_source ]]; then
    log "INFO" "Reading domains from file: ${domains_source}"
    mapfile -t domains < <(grep -v -e '^$' -e '^[[:space:]]*#' <"$domains_source")
  else
    log "INFO" "Parsing domains from comma-separated string."
    IFS=',' read -r -a domains <<<"$domains_source"
  fi

  if [[ ${#domains[@]} -eq 0 ]]; then
    log "ERROR" "No domains found to process." >&2
    exit 1
  fi

  # --- Process Domains ---
  log "INFO" "Starting DKIM key generation for ${#domains[@]} domain(s)..."
  local success_count=0
  local failure_count=0

  for domain in "${domains[@]}"; do
    local clean_domain
    clean_domain="$(echo -n "${domain}" | xargs)"
    if [[ -z $clean_domain ]]; then
      continue
    fi

    if gen_key_pair "$clean_domain" "$output_dir" "$key_bits"; then
      success_count=$((success_count + 1))
    else
      failure_count=$((failure_count + 1))
    fi
  done

  # --- Final Summary ---
  log "SUCCESS" "DKIM key generation complete."
  log "INFO" "Summary: ${success_count} successful, ${failure_count} failed out of ${#domains[@]} total domains."

  if [[ $failure_count -gt 0 ]]; then
    exit 1
  fi
  exit 0

}
main "$@"
