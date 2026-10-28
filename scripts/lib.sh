#!/usr/bin/env bash
# Shared config + helpers for all k8s-lab scripts.
# This file is SOURCED by the other scripts, not executed directly.
set -euo pipefail

# Make user-local tool installs visible even when ~/.local/bin isn't on PATH
# (kind/helm are installed there without sudo — see install-tools.sh).
export PATH="${HOME}/.local/bin:${PATH}"

# ----------------------------------------------------------------------------
# Pinned versions — the single source of truth for the whole lab.
# ----------------------------------------------------------------------------
CLUSTER_NAME="k8s-lab"
TERRAFORM_VERSION="1.17.0"
KIND_VERSION="v0.32.0"
HELM_VERSION="v4.2.2"
KUBECTL_VERSION="v1.36.1"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"
# Terraform writes the cluster's kubeconfig here (stable path; see terraform/variables.tf).
export KUBECONFIG="${KUBECONFIG_PATH:-${HOME}/.kube/k8s-lab.config}"
# Host port Traefik is published on (terraform var http_port).
HTTP_PORT="28080"

# Headlamp web dashboard (installed via upstream Helm chart, exposed via ingress)
HEADLAMP_REPO="https://kubernetes-sigs.github.io/headlamp/"
HEADLAMP_CHART_VERSION="0.43.0"
DASHBOARD_NS="headlamp"
DASHBOARD_HOST="dashboard.localhost"

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${LIB_DIR}/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"

# ----------------------------------------------------------------------------
# Logging helpers
# ----------------------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Echo "os arch" using Go-style names (linux amd64 / darwin arm64 / ...).
os_arch() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported CPU arch: $(uname -m)" ;;
  esac
  printf '%s %s' "${os}" "${arch}"
}

require_docker() {
  have docker || die "docker not found — start Docker Desktop with WSL2 integration."
  docker info >/dev/null 2>&1 || die "docker daemon unreachable — is Docker Desktop running?"
}

# ----------------------------------------------------------------------------
# Tool installers — idempotent, user-local (~/.local/bin), no sudo required.
# ----------------------------------------------------------------------------
ensure_bindir() { mkdir -p "${BIN_DIR}"; }

ensure_kubectl() {
  # Match the pinned version (so a differently-versioned system kubectl gets
  # superseded by one in ~/.local/bin, which is earlier on PATH).
  if have kubectl && kubectl version --client 2>/dev/null | grep -q "${KUBECTL_VERSION}"; then
    ok "kubectl present ($(kubectl version --client 2>/dev/null | head -1))"; return
  fi
  local os arch; read -r os arch <<<"$(os_arch)"
  log "installing kubectl ${KUBECTL_VERSION} -> ${BIN_DIR}"
  ensure_bindir
  curl -fsSL -o "${BIN_DIR}/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${os}/${arch}/kubectl"
  chmod +x "${BIN_DIR}/kubectl"
  ok "kubectl installed ($(kubectl version --client 2>/dev/null | head -1))"
}

ensure_kind() {
  if have kind && kind --version 2>/dev/null | grep -q "${KIND_VERSION#v}"; then
    ok "kind present ($(kind --version))"; return
  fi
  local os arch; read -r os arch <<<"$(os_arch)"
  log "installing kind ${KIND_VERSION} -> ${BIN_DIR}"
  ensure_bindir
  curl -fsSL -o "${BIN_DIR}/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${os}-${arch}"
  chmod +x "${BIN_DIR}/kind"
  ok "kind installed ($(kind --version))"
}

ensure_helm() {
  if have helm && helm version --short 2>/dev/null | grep -q "${HELM_VERSION}"; then
    ok "helm present ($(helm version --short))"; return
  fi
  local os arch; read -r os arch <<<"$(os_arch)"
  log "installing helm ${HELM_VERSION} -> ${BIN_DIR}"
  ensure_bindir
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-${os}-${arch}.tar.gz"
  tar -xzf "${tmp}/helm.tgz" -C "${tmp}"
  install -m 0755 "${tmp}/${os}-${arch}/helm" "${BIN_DIR}/helm"
  rm -rf "${tmp}"
  ok "helm installed ($(helm version --short))"
}

ensure_terraform() {
  if have terraform && terraform version 2>/dev/null | head -1 | grep -q "${TERRAFORM_VERSION}"; then
    ok "terraform present ($(terraform version | head -1))"; return
  fi
  local os arch; read -r os arch <<<"$(os_arch)"
  log "installing terraform ${TERRAFORM_VERSION} -> ${BIN_DIR}"
  ensure_bindir
  local tmp base zip; tmp="$(mktemp -d)"
  base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"
  zip="terraform_${TERRAFORM_VERSION}_${os}_${arch}.zip"
  curl -fsSL -o "${tmp}/${zip}" "${base}/${zip}"
  curl -fsSL -o "${tmp}/SHA256SUMS" "${base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
  (cd "${tmp}" && grep " ${zip}\$" SHA256SUMS | sha256sum -c -)
  python3 -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extract('terraform', sys.argv[2])" "${tmp}/${zip}" "${tmp}"
  install -m 0755 "${tmp}/terraform" "${BIN_DIR}/terraform"
  rm -rf "${tmp}"
  ok "terraform installed ($(terraform version | head -1))"
}

ensure_tools() { ensure_bindir; ensure_terraform; ensure_kubectl; ensure_kind; ensure_helm; }

print_versions() {
  log "tool versions"
  printf '  terraform: %s
' "$(terraform version 2>/dev/null | head -1 || echo MISSING)"
  printf '  kubectl : %s\n' "$(kubectl version --client 2>/dev/null | head -1)"
  printf '  kind    : %s\n' "$(kind --version 2>/dev/null || echo MISSING)"
  printf '  helm    : %s\n' "$(helm version --short 2>/dev/null || echo MISSING)"
  printf '  docker  : %s\n' "$(docker --version 2>/dev/null || echo MISSING)"
}

# Guard: fail early with a friendly message if the cluster isn't up.
require_cluster() {
  kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}" \
    || die "cluster '${CLUSTER_NAME}' not found. Run 'make up' (or ./lab up) first."
}
