terraform {
  required_version = ">= 1.9.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.13.0"
    }
    # helm 3.x changed the provider block syntax (kubernetes = {...}); stay on 2.x.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

# The helm provider talks to the cluster Terraform itself creates. Its
# connection values are unknown until the cluster exists, which the provider
# tolerates as long as every helm_release depends on the cluster.
provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}
