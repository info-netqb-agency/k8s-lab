output "kubeconfig_path" {
  value = local.kubeconfig_path
}

output "export_command" {
  value = "export KUBECONFIG=${local.kubeconfig_path}"
}

output "hello_url" {
  value = "http://hello.localhost:${var.http_port}"
}

output "argocd_url" {
  value = "http://${var.argocd_host}:${var.http_port}"
}
