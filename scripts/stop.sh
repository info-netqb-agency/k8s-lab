#!/usr/bin/env bash
# Stop the cluster's node containers WITHOUT deleting them (preserves all state).
# Resume later with 'make start'. Use 'make down' to actually delete the cluster.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
require_cluster
nodes="$(kind get nodes --name "${CLUSTER_NAME}")"
log "stopping cluster '${CLUSTER_NAME}' node containers (state preserved)"
# shellcheck disable=SC2086
docker stop ${nodes} >/dev/null
ok "cluster stopped — resume with 'make start' (or ./lab start)"
