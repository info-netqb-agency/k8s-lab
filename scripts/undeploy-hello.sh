#!/usr/bin/env bash
# Remove the 'hello' demo chart. Idempotent — no-op if not installed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
ensure_helm

if helm --kube-context "${KUBE_CONTEXT}" -n hello status hello >/dev/null 2>&1; then
  log "uninstalling 'hello' release"
  helm --kube-context "${KUBE_CONTEXT}" uninstall hello -n hello
  kubectl --context "${KUBE_CONTEXT}" delete namespace hello --ignore-not-found
  ok "hello removed"
else
  ok "'hello' release not installed — nothing to do"
fi
