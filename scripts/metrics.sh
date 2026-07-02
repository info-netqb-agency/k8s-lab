#!/usr/bin/env bash
# Install metrics-server so `kubectl top` and Headlamp usage graphs work.
# Idempotent via `helm upgrade --install`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
ensure_helm
cd "${ROOT_DIR}"

log "adding/updating the metrics-server Helm repo"
helm repo add metrics-server "${METRICS_REPO}" >/dev/null 2>&1 || true
helm repo update metrics-server >/dev/null

log "deploying metrics-server ${METRICS_CHART_VERSION} (namespace: ${METRICS_NS})"
helm --kube-context "${KUBE_CONTEXT}" upgrade --install metrics-server metrics-server/metrics-server \
  --version "${METRICS_CHART_VERSION}" \
  --namespace "${METRICS_NS}" \
  -f metrics/values.yaml \
  --wait --timeout 180s

log "waiting for the metrics API to serve data (first scrape takes ~15-30s)"
ok_top=0
for i in $(seq 1 20); do
  if kubectl --context "${KUBE_CONTEXT}" top nodes >/dev/null 2>&1; then ok_top=1; break; fi
  sleep 5
done
[ "${ok_top}" = "1" ] || die "metrics API did not become ready in time (check: kubectl -n ${METRICS_NS} logs deploy/metrics-server)"

ok "metrics-server is ready"
echo
log "kubectl top nodes"
kubectl --context "${KUBE_CONTEXT}" top nodes
echo
log "kubectl top pods (all namespaces, top 10 by CPU)"
# awk (not head) so kubectl isn't killed by SIGPIPE under `set -o pipefail`.
kubectl --context "${KUBE_CONTEXT}" top pods -A --sort-by=cpu 2>/dev/null | awk 'NR<=11'
cat <<EOF

Usage data is now live. Try:
  kubectl top nodes
  kubectl top pods -A
In Headlamp, the CPU/Memory tiles on nodes, pods and workloads now populate.
EOF
