#!/usr/bin/env bash
# Install the Headlamp web dashboard via Helm and expose it through Traefik
# at http://dashboard.localhost:${HTTP_PORT}. Idempotent via `helm upgrade --install`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
ensure_helm
cd "${ROOT_DIR}"

log "adding/updating the headlamp Helm repo"
helm repo add headlamp "${HEADLAMP_REPO}" >/dev/null 2>&1 || true
helm repo update headlamp >/dev/null

log "deploying Headlamp ${HEADLAMP_CHART_VERSION} (namespace: ${DASHBOARD_NS})"
helm --kube-context "${KUBE_CONTEXT}" upgrade --install headlamp headlamp/headlamp \
  --version "${HEADLAMP_CHART_VERSION}" \
  --namespace "${DASHBOARD_NS}" --create-namespace \
  -f dashboard/values.yaml \
  --wait --timeout 180s

log "creating cluster-admin login identity (headlamp-admin ServiceAccount)"
kubectl --context "${KUBE_CONTEXT}" apply -f dashboard/admin.yaml

log "waiting for the Headlamp rollout"
kubectl --context "${KUBE_CONTEXT}" -n "${DASHBOARD_NS}" rollout status \
  deployment/headlamp --timeout=180s
ok "Headlamp is ready"

echo
log "log in with this token (valid 24h):"
kubectl --context "${KUBE_CONTEXT}" -n "${DASHBOARD_NS}" create token headlamp-admin --duration=24h
cat <<EOF

Open the dashboard:
  Browser : http://${DASHBOARD_HOST}:${HTTP_PORT}
  Paste the token above at the login screen.
  Reprint a fresh token any time with: make dashboard-token   (or ./lab dashboard-token)
EOF
