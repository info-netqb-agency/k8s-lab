#!/usr/bin/env bash
# Show cluster nodes (wide), all pods, and Argo CD application status.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
log "nodes"
kubectl get nodes -o wide
echo
log "pods (all namespaces)"
kubectl get pods -A
echo
log "argo cd applications"
kubectl -n argocd get applications.argoproj.io 2>/dev/null || warn "no Argo CD applications yet"
