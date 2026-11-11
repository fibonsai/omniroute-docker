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
#   OMNIROUTE_API_KEY  Key agents present to reach the OmniRoute gateway
#   NVIDIA_API_KEY, DEEPSEEK_API_KEY, GEMINI_API_KEY, ...   upstream keys
#
# Example:
#   export INITIAL_PASSWORD='password'
#   export OMNIROUTE_API_KEY='omni-...'
#   export NVIDIA_API_KEY='nvapi-...'
#   ./run-openshell.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
INITIAL_PASSWORD="${INITIAL_PASSWORD:-password}"
PROFILE="openshell/inference-providers.yaml"
SANDBOX_NAME="omniroute"
OMNIROUTE_IMAGE="local/omniroute"   # build your OmniRoute image first (see README)
OMNIROUTE_PORT="20128"

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

# The OMNIROUTE_API_KEY is the key agents use to reach OmniRoute. It must be
# present so OpenShell can bind it to the sandbox.
[[ -n "${OMNIROUTE_API_KEY:-}" ]] || die "OMNIROUTE_API_KEY is not set. Export it (the key agents present to reach OmniRoute)."

log "Linting profile $PROFILE ..."
openshell profile lint -f "$PROFILE" >/dev/null

log "Importing profile $PROFILE ..."
openshell profile import -f "$PROFILE" >/dev/null

# ---------------------------------------------------------------------------
# Create (or reuse) the OmniRoute sandbox
# ---------------------------------------------------------------------------
if openshell sandbox inspect "$SANDBOX_NAME" >/dev/null 2>&1; then
  log "Sandbox '$SANDBOX_NAME' already exists; reusing it."
else
  log "Creating sandbox '$SANDBOX_NAME' from $OMNIROUTE_IMAGE ..."
  openshell sandbox create \
    --name "$SANDBOX_NAME" \
    --from "$OMNIROUTE_IMAGE" \
    --provider inference-providers \
    --env INITIAL_PASSWORD="$INITIAL_PASSWORD" \
    --env OMNIROUTE_API_KEY="$OMNIROUTE_API_KEY" \
    -- omniroute --daemon
fi

# ---------------------------------------------------------------------------
# Wait for OmniRoute to be reachable
# ---------------------------------------------------------------------------
log "Waiting for OmniRoute on host.openshell.internal:$OMNIROUTE_PORT ..."
for i in $(seq 1 30); do
  if openshell sandbox exec -n "$SANDBOX_NAME" -- \
     sh -c "command -v curl >/dev/null 2>&1 && curl -fsS http://host.openshell.internal:$OMNIROUTE_PORT/login >/dev/null 2>&1"; then
    log "OmniRoute is reachable."
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    die "OmniRoute did not become reachable on host.openshell.internal:$OMNIROUTE_PORT"
  fi
  sleep 2
done

log "OmniRoute sandbox '$SANDBOX_NAME' is up using profile inference-providers."
log "Agents connect with OMNIROUTE_API_KEY to host.openshell.internal:$OMNIROUTE_PORT/v1"
log "Upstream {PROVIDER}_API_KEY values are held only by this sandbox (see $PROFILE)."
