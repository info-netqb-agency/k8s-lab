#!/usr/bin/env bash
# Delete the kind cluster. Idempotent — safe to run when nothing exists.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "deleting kind cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "${CLUSTER_NAME}"
  ok "cluster deleted"
else
  ok "cluster '${CLUSTER_NAME}' not present — nothing to delete"
fi
