#!/usr/bin/env bash
# Deploy the 'hello' demo chart. Idempotent via `helm upgrade --install`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cluster
ensure_helm
cd "${ROOT_DIR}"

log "deploying 'hello' chart (namespace: hello)"
helm --kube-context "${KUBE_CONTEXT}" upgrade --install hello charts/hello \
  --namespace hello --create-namespace --wait --timeout 120s
ok "hello deployed"

cat <<'EOF'

Reach the demo app:
  Browser : http://hello.localhost
  curl    : curl -H 'Host: hello.localhost' http://localhost
EOF
