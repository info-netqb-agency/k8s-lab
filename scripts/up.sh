#!/usr/bin/env bash
# Create the 4-node kind cluster from kind-config.yaml. Idempotent.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
ensure_kind
ensure_kubectl
cd "${ROOT_DIR}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  ok "cluster '${CLUSTER_NAME}' already exists — nothing to do (use 'reset' to recreate)"
else
  log "creating kind cluster '${CLUSTER_NAME}' (1 control-plane + 3 workers)"
  kind create cluster --name "${CLUSTER_NAME}" --config kind-config.yaml --wait 120s
  ok "cluster created"
fi

# ingress-nginx (kind provider) schedules its controller onto the node labeled
# ingress-ready=true. Label the control-plane node here (idempotent) — done at
# runtime rather than via a kubeadm patch so it survives kubeadm API changes.
log "labeling control-plane node ingress-ready=true"
kubectl --context "${KUBE_CONTEXT}" label node "${CLUSTER_NAME}-control-plane" \
  ingress-ready=true --overwrite >/dev/null
kubectl config use-context "${KUBE_CONTEXT}" >/dev/null

# Manual-start-only: kind defaults the node containers to on-failure, which can
# auto-start the whole cluster on Docker/host restart. Force 'no' so the cluster
# only runs when you explicitly 'make up' / 'make start'.
log "disabling node auto-start (restart=no)"
# shellcheck disable=SC2046
docker update --restart=no $(kind get nodes --name "${CLUSTER_NAME}") >/dev/null
ok "cluster ready; kube-context set to ${KUBE_CONTEXT}"
