#!/usr/bin/env bash
# Install the ingress-nginx controller (kind provider) and wait until ready.
# Idempotent: kubectl apply is declarative; re-running just reconciles.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
cd "${ROOT_DIR}"

log "ensuring control-plane is labeled ingress-ready=true"
kubectl --context "${KUBE_CONTEXT}" label node "${CLUSTER_NAME}-control-plane" \
  ingress-ready=true --overwrite >/dev/null

log "applying ingress-nginx (controller-v1.15.1, vendored kind manifest)"
kubectl --context "${KUBE_CONTEXT}" apply -f "${INGRESS_MANIFEST}"

# The admission webhook certgen jobs must finish before the controller serves.
log "waiting for admission certgen jobs"
kubectl --context "${KUBE_CONTEXT}" -n ingress-nginx wait \
  --for=condition=complete job --all --timeout=180s 2>/dev/null || true

log "waiting for the ingress-nginx controller pod to be ready"
kubectl --context "${KUBE_CONTEXT}" -n ingress-nginx wait \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
ok "ingress-nginx is ready (listening on host :80 and :443)"
