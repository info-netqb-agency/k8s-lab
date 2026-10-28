#!/usr/bin/env bash
# Create the whole lab with Terraform: kind cluster, Cilium, Traefik,
# metrics-server, Argo CD and the hello Application. Idempotent.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
ensure_terraform
ensure_kubectl
cd "${ROOT_DIR}/terraform"

log "terraform init"
terraform init -input=false
log "terraform apply"
terraform apply -auto-approve -input=false

echo
ok "lab is up"
terraform output -raw export_command | sed 's/^/  /'
echo
echo "  hello  : $(terraform output -raw hello_url)"
echo "  argocd : $(terraform output -raw argocd_url)"
