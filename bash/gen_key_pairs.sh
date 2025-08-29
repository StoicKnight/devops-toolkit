#!/bin/env bash

set -e

# --- Config ---
DOMAIN_LIST="/etc/exim4/dkim/domainlist.txt"
DKIM_DIR="/etc/exim4/dkim"
EXIM_USER="Debian-exim"
EXIM_GROUP="Debian-exim"

# --- Help Functions ---
usage() {
  cat <<EOF

Usage: ${SCRIPT_NAME} [OPTIONS]

Arguments:

Options:
  -h, --help      Display this help and exit.
  -o, --output    Overwrite the default output path.
  -v, --verbose   Increase verbosity.

Usage:

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
  for cmd in openssl; do
    if ! command -v "$cmd" &>/dev/null; then
      log "ERROR" "Required command '${cmd}' is not installed or not in your PATH." >&2
      missing_deps=1
    fi
  done
  if [[ $missing_deps -eq 1 ]]; then
    exit 1
  fi
}

main() {
  local verbose=false
  local output_path=""
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
        output_path="$2"
        shift 2
        ;;
      -v | --verbose)
        verbose=true
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

  arg="${positional_args[0]}"

  # --- Validation ---
  if [ ! -f "$DOMAIN_LIST" ]; then
    log "ERROR" "Domain list file not found at $DOMAIN_LIST"
    exit 1
  fi

  log "INFO" "Starting DKIM key generation..."

  # --- Proccess Domains ---
  while IFS= read -r DOMAIN || [[ -n $DOMAIN ]]; do
    if [ -z "$DOMAIN" ]; then
      continue
    fi

    PRIVATE_KEY_PATH="$DKIM_DIR/$DOMAIN.priv.key"
    PUBLIC_KEY_PATH="$DKIM_DIR/$DOMAIN.pub.pem"

    log "INFO" "Processing domain: $DOMAIN"

    if [ -f "$PRIVATE_KEY_PATH" ]; then
      log "WARNING" "Skipping: Private key already exists at $PRIVATE_KEY_PATH"
      continue
    fi

    log "INFO" "Generating 2048-bit private key..."
    openssl genrsa -out "$PRIVATE_KEY_PATH" 2048

    log "INFO" "Extracting public key..."
    openssl rsa -in "$PRIVATE_KEY_PATH" -pubout -out "$PUBLIC_KEY_PATH"

    log "INFO" "Setting ownership and permissions..."
    chown "$EXIM_USER:$EXIM_GROUP" "$PRIVATE_KEY_PATH"
    chmod 640 "$PRIVATE_KEY_PATH"

    echo "Successfully created keys for $DOMAIN."

  done <"$DOMAIN_LIST"

  log "SUCCESS" "All ${#DOMAIN_LIST[@]} done!"

}
main "$@"
