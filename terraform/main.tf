locals {
  use_cilium      = var.cni == "cilium"
  kubeconfig_path = pathexpand(var.kubeconfig_path)
}

# ---------------------------------------------------------------------------
# Cluster: 1 control-plane + var.worker_count workers
# ---------------------------------------------------------------------------
resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = local.kubeconfig_path

  # With Cilium the nodes only turn Ready once the CNI is installed, so waiting
  # here would deadlock.
  wait_for_ready = !local.use_cilium

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      disable_default_cni = local.use_cilium
    }

    node {
      role = "control-plane"

      # Traefik is pinned to this node and publishes hostPorts on it.
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = var.http_port
        host_port      = var.http_port
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = var.https_port
        host_port      = var.https_port
        protocol       = "TCP"
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

# Node containers must never auto-start with Docker (manual start only).
resource "terraform_data" "restart_no" {
  triggers_replace = [kind_cluster.this.id]

  provisioner "local-exec" {
    command = "docker update --restart=no $(docker ps -aq --filter label=io.x-k8s.kind.cluster=${var.cluster_name})"
  }
}

# ---------------------------------------------------------------------------
# CNI
# ---------------------------------------------------------------------------
resource "helm_release" "cilium" {
  count = local.use_cilium ? 1 : 0

  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_chart_version
  timeout    = 600

  values = [yamlencode({
    ipam                 = { mode = "kubernetes" }
    operator             = { replicas = 1 }
    kubeProxyReplacement = false
    # kind nodes share one L2 Docker bridge, so use native routing instead of a
    # VXLAN tunnel. The native-routing CIDR (kind's default pod CIDR) also makes
    # Cilium masquerade pod -> node-IP traffic; in tunnel mode pods could not
    # reach other nodes' IPs (e.g. the API server), which broke metrics-server.
    routingMode           = "native"
    autoDirectNodeRoutes  = true
    ipv4NativeRoutingCIDR = "10.244.0.0/16"
  })]

  depends_on = [kind_cluster.this]
}

# Everything below needs a working pod network.
resource "terraform_data" "cni_ready" {
  input      = var.cni
  depends_on = [kind_cluster.this, helm_release.cilium]
}

# ---------------------------------------------------------------------------
# Ingress: Traefik on the control-plane node, hostPort -> kind port mapping
# ---------------------------------------------------------------------------
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  timeout          = 300

  values = [yamlencode({
    deployment   = { replicas = 1 }
    ingressClass = { enabled = true, isDefaultClass = true }
    service      = { spec = { type = "ClusterIP" } }
    ports = {
      web       = { hostPort = var.http_port }
      websecure = { hostPort = var.https_port }
    }
    nodeSelector = { "ingress-ready" = "true" }
    tolerations = [{
      key      = "node-role.kubernetes.io/control-plane"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  })]

  depends_on = [terraform_data.cni_ready]
}

# ---------------------------------------------------------------------------
# metrics-server (kind kubelets use self-signed certs)
# ---------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  timeout    = 300

  values = [yamlencode({
    args = ["--kubelet-insecure-tls"]
  })]

  depends_on = [terraform_data.cni_ready]
}

# ---------------------------------------------------------------------------
# Argo CD, served through Traefik (plain HTTP behind the ingress)
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = 600

  values = [yamlencode({
    # The chart's default NetworkPolicies drop the kubelet's health probes under
    # Cilium (host traffic is classified as "world"), leaving repo-server and the
    # application controller NotReady. A local lab does not need them.
    global  = { domain = var.argocd_host, networkPolicy = { create = false } }
    configs = { params = { "server.insecure" = true } }
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hostname         = var.argocd_host
      }
    }
  })]

  depends_on = [helm_release.traefik]
}

# ---------------------------------------------------------------------------
# GitOps hand-off: one Application; Git owns the workloads from here on.
# ---------------------------------------------------------------------------
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      hello = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.hello_repo_url
          targetRevision = var.hello_repo_revision
          path           = var.hello_chart_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "hello"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
