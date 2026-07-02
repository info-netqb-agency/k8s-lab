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

# The v1.15.1 kind manifest only constrains the controller to linux nodes, so
# the scheduler may place it on a worker. But only the control-plane node has the
# host port mappings (80/443). Pin the controller to the ingress-ready node so
# its hostPort binds where the traffic actually arrives. Idempotent merge patch.
log "pinning controller to the ingress-ready (control-plane) node"
kubectl --context "${KUBE_CONTEXT}" -n ingress-nginx patch deployment ingress-nginx-controller \
  --type merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","ingress-ready":"true"}}}}}'

# The admission webhook certgen jobs must finish before the controller serves.
log "waiting for admission certgen jobs"
kubectl --context "${KUBE_CONTEXT}" -n ingress-nginx wait \
  --for=condition=complete job --all --timeout=180s 2>/dev/null || true

log "waiting for the ingress-nginx controller rollout"
kubectl --context "${KUBE_CONTEXT}" -n ingress-nginx rollout status \
  deployment/ingress-nginx-controller --timeout=180s
ok "ingress-nginx is ready (controller on control-plane, host :80 and :443)"
