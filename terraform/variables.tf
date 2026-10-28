variable "cluster_name" {
  description = "Name of the kind cluster (kubectl context becomes kind-<name>)."
  type        = string
  default     = "k8s-lab"
}

variable "worker_count" {
  description = "Number of worker nodes (in addition to the single control-plane)."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 10
    error_message = "worker_count must be between 0 and 10."
  }
}

variable "node_image" {
  description = "kindest/node image, pinned by version and digest."
  type        = string
  default     = "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
}

variable "kubeconfig_path" {
  description = "Stable path the cluster's kubeconfig is written to."
  type        = string
  default     = "~/.kube/k8s-lab.config"
}

variable "cni" {
  description = "CNI to use: \"cilium\" (default CNI disabled, Cilium installed) or \"kindnet\" (kind's built-in)."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["cilium", "kindnet"], var.cni)
    error_message = "cni must be \"cilium\" or \"kindnet\"."
  }
}

variable "http_port" {
  description = "Host port mapped to the Traefik HTTP entrypoint (deliberately not 80/8080)."
  type        = number
  default     = 28080
}

variable "https_port" {
  description = "Host port mapped to the Traefik HTTPS entrypoint (deliberately not 443/8443)."
  type        = number
  default     = 28443
}

variable "argocd_host" {
  description = "Hostname Argo CD is served on through Traefik (*.localtest.me resolves to 127.0.0.1)."
  type        = string
  default     = "argocd.localtest.me"
}

variable "hello_repo_url" {
  description = "Git repo Argo CD pulls charts/hello from. Must be reachable from inside the cluster (public HTTPS URL)."
  type        = string
  default     = "https://github.com/CHANGE-ME/k8s-lab.git"
}

variable "hello_repo_revision" {
  description = "Branch, tag or commit of hello_repo_url to deploy."
  type        = string
  default     = "HEAD"
}

variable "hello_chart_path" {
  description = "Path of the hello Helm chart inside the repo."
  type        = string
  default     = "charts/hello"
}

# Chart versions - all pinned.
variable "cilium_chart_version" {
  type    = string
  default = "1.20.4"
}

variable "traefik_chart_version" {
  type    = string
  default = "42.1.3" # Traefik v3.7.16
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.13.1" # metrics-server v0.8.1
}

variable "argocd_chart_version" {
  type    = string
  default = "10.11.6" # Argo CD v3.5.6
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.7"
}
