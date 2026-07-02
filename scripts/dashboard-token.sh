#!/usr/bin/env bash
# Print a fresh 24h login token for the Headlamp dashboard.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
if ! kubectl --context "${KUBE_CONTEXT}" -n "${DASHBOARD_NS}" get sa headlamp-admin >/dev/null 2>&1; then
  die "headlamp-admin not found. Run 'make dashboard' (or ./lab dashboard) first."
fi
kubectl --context "${KUBE_CONTEXT}" -n "${DASHBOARD_NS}" create token headlamp-admin --duration=24h
