#!/usr/bin/env bash
# Remove the Headlamp dashboard. Idempotent — no-op if not installed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
ensure_helm

if helm --kube-context "${KUBE_CONTEXT}" -n "${DASHBOARD_NS}" status headlamp >/dev/null 2>&1; then
  log "uninstalling Headlamp"
  helm --kube-context "${KUBE_CONTEXT}" uninstall headlamp -n "${DASHBOARD_NS}"
else
  ok "Headlamp release not installed"
fi
kubectl --context "${KUBE_CONTEXT}" delete clusterrolebinding headlamp-admin --ignore-not-found
kubectl --context "${KUBE_CONTEXT}" delete namespace "${DASHBOARD_NS}" --ignore-not-found
ok "Headlamp removed"
