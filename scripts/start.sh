#!/usr/bin/env bash
# Start a previously 'stop'ped cluster and wait for its nodes to be Ready.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
require_cluster
nodes="$(kind get nodes --name "${CLUSTER_NAME}")"
log "starting cluster '${CLUSTER_NAME}' node containers"
# shellcheck disable=SC2086
docker start ${nodes} >/dev/null

log "waiting for all nodes to be Ready (up to 120s)"
for _ in $(seq 1 24); do
  ready="$(kubectl --context "${KUBE_CONTEXT}" get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
  [ "${ready}" = "$(echo "${nodes}" | wc -w)" ] && { ok "all nodes Ready"; exit 0; }
  sleep 5
done
warn "nodes not all Ready yet — check 'make status'"
