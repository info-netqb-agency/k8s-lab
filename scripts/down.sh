#!/usr/bin/env bash
# Destroy the lab with Terraform. Idempotent — safe when nothing exists.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
ensure_terraform
cd "${ROOT_DIR}/terraform"

if [ -d .terraform ] || terraform init -input=false >/dev/null 2>&1; then
  if [ -f terraform.tfstate ] && [ "$(terraform state list 2>/dev/null | wc -l)" -gt 0 ]; then
    log "terraform destroy"
    terraform destroy -auto-approve -input=false
    ok "lab destroyed"
    exit 0
  fi
fi

# No Terraform state: remove a cluster created by hand / by the old scripts.
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  warn "no Terraform state, but kind cluster '${CLUSTER_NAME}' exists — deleting it with kind"
  kind delete cluster --name "${CLUSTER_NAME}"
else
  ok "nothing to destroy"
fi
