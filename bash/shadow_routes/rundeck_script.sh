#!/bin/env bash

set -e

EMAILS="$1"
FORCE="$2"
VERBOSE="$3"
SERVICE="$4"

PILLAR_JSON=$(
  cat <<EOF
{
  "emails": "$EMAILS",
  "force": $FORCE,
  "verbose": $VERBOSE,
  "service": "$SERVICE"
}
EOF
)

PILLAR_JSON_SINGLE_LINE=$(echo "$PILLAR_JSON" | tr -d '\n' | tr -s ' ')

# --- DEBUG PILLAR ---
echo "--- Generated Pillar JSON for Salt ---"
echo "$PILLAR_JSON_SINGLE_LINE"
echo "--------------------------------------"

salt "<minion-id>" state.apply shadow_routes.add_shadow_routes \
  pillar="${PILLAR_JSON_SINGLE_LINE}" \
  saltenv=infra -t 60
