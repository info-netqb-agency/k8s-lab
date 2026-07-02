#!/usr/bin/env bash
# Show cluster nodes (wide) and all pods across namespaces.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
log "nodes"
kubectl --context "${KUBE_CONTEXT}" get nodes -o wide
echo
log "pods (all namespaces)"
kubectl --context "${KUBE_CONTEXT}" get pods -A
