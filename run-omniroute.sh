#!/usr/bin/env bash
#
# run-openshell.sh — Launch OmniRoute inside an OpenShell sandbox using the
# inference-providers profile.
#
# This starts OmniRoute (omniroute --daemon) inside an OpenShell sandbox backed
# by the inference-providers profile (openshell/inference-providers.yaml). The
# sandbox holds all {PROVIDER}_API_KEY values and binds each to its respective
# provider endpoint. Agent sandboxes (omniroute-agent profile) reach OmniRoute
# only through OMNIROUTE_API_KEY and never see upstream provider keys.
#
# Required environment (set before running, or export in this shell):
#   INITIAL_PASSWORD   OmniRoute initial admin password (default: password)
#   NVIDIA_API_KEY, DEEPSEEK_API_KEY, GEMINI_API_KEY, ...   upstream keys
#
# Example:
#   export INITIAL_PASSWORD='password'
#   export NVIDIA_API_KEY='nvapi-...'
#   ./run-omniroute.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
INITIAL_PASSWORD="${INITIAL_PASSWORD:-password}"
PROFILE="openshell/inference-providers.yaml"
POLICY="openshell/policy.yaml"
SANDBOX_NAME="omniroute"
OMNIROUTE_IMAGE="localhost/fibonsai/omniroute:latest"  # build your OmniRoute image first (see README)
OMNIROUTE_PORT="20128"
DRIVER="`grep compute_driver ~/.config/openshell/gateway.toml | cut -d'"' -f2`"
RESET_ALL_KEYS="${RESET_ALL_KEYS:-true}"

openshell sandbox get $SANDBOX_NAME > /dev/null 2>&1 && openshell sandbox delete $SANDBOX_NAME && sleep 5

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[run-openshell] %s\n' "$*" >&2; }
die()  { printf '[run-openshell] ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_cmd openshell

[[ -f "$PROFILE" ]] || die "profile not found: $PWD/$PROFILE"

PROFILE_NAME=`grep '^id:' "$PROFILE"| sed 's/.*: //'`
if [ "x`openshell provider list| grep $PROFILE_NAME`" != "x" ]; then
   openshell provider delete $PROFILE_NAME
fi
if [ "x`openshell profile list| grep $PROFILE_NAME`" != "x" ]; then
   openshell profile delete $PROFILE_NAME
fi

log "Linting profile $PROFILE ..."
openshell profile lint -f "$PROFILE" >/dev/null

log "Importing profile $PROFILE ..."
openshell profile import -f "$PROFILE" >/dev/null

log "Creating provider $PROFILE ..."
openshell provider create --name $PROFILE_NAME --type $PROFILE_NAME

log "Using $DRIVER"

log "Creating omniroute-data volume (if necessary)"
$DRIVER volume exists omniroute-data && echo "omniroute-data volume already exists" || \
$DRIVER volume create \
  --label openshell.ai/sandbox-attachable=true \
  --label openshell.ai/sandbox-attachable-workspace=default \
  omniroute-data

# ---------------------------------------------------------------------------
# Create the OmniRoute sandbox
# ---------------------------------------------------------------------------
log "Creating sandbox '$SANDBOX_NAME' from $OMNIROUTE_IMAGE ..."
openshell sandbox create \
    --name "$SANDBOX_NAME" \
    --from "$OMNIROUTE_IMAGE" \
    --provider "$PROFILE_NAME" \
    --policy "$POLICY" \
    --expose 20128 \
    --driver-config-json '{"'$DRIVER'":{"mounts":[{"type":"volume","source":"omniroute-data","target":"/home/node/.omniroute","read_only":false}]}}' \
    --detach \
    -- omniroute --no-open --log --no-recovery

# ---------------------------------------------------------------------------
# Wait for OmniRoute to be reachable
# ---------------------------------------------------------------------------
log "Waiting for OmniRoute on 127.0.0.1:$OMNIROUTE_PORT ..."
for i in $(seq 1 30); do
  if openshell sandbox exec -n "$SANDBOX_NAME" -- \
     sh -c "command -v curl >/dev/null 2>&1 && curl -fsS http://127.0.0.1:$OMNIROUTE_PORT/login >/dev/null 2>&1"; then
    log "OmniRoute is reachable."
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    die "OmniRoute did not become reachable on 127.0.0.1:$OMNIROUTE_PORT"
  fi
  sleep 2
done

log "Updating dashboard password"
openshell sandbox exec -n "$SANDBOX_NAME" -- omniroute setup --non-interactive --password "$INITIAL_PASSWORD" 2> /dev/null | grep -v 'Loaded '

if [ "x$RESET_ALL_KEYS" == "xtrue" ]; then
  log "Reset all old keys"
  openshell sandbox exec -n "$SANDBOX_NAME" -- sh -c "omniroute --quiet --output json api api-keys get-api-keys 2> /dev/null | grep -v 'Loaded ' | grep '\"id\":'| cut -d'\"' -f4 | while read id; do omniroute --quiet api api-keys delete-api-keys-id- --id \$id 2> /dev/null | grep -v 'Loaded ' | sed \"s/.*/key \$id removed/\"; done | uniq"
fi

OMNIROUTE_API_KEY="`openshell sandbox exec -n "$SANDBOX_NAME" -- omniroute --quiet --output json api api-keys post-api-keys --body '{"name": "default"}' 2>/dev/null |grep '"key"' | cut -d'"' -f4`"
echo -n "OMNIROUTE_API_KEY=${OMNIROUTE_API_KEY}" > .env 

LOCAL_SERVICE=`openshell service list -o json | jq -r '.services[] | select (.sandbox = "'$SANDBOX_NAME'")| .url'`

log "OmniRoute sandbox '$SANDBOX_NAME' is up using profile inference-providers."
log "OmniRoute OMNIROUTE_API_KEY is saved in '.env' file (always refreshed when reexecuting this script)"
log "Local access: ${LOCAL_SERVICE}/v1"
log "Upstream {PROVIDER}_API_KEY values are held only by this sandbox (see $PROFILE)."
