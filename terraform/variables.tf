variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.3.4"
}

variable "tenants" {
  description = "List of tenant namespaces to create"
  type = list(object({
    name       = string
    memory_limit = string
    cpu_limit    = string
    gpu_limit    = string
  }))
  default = [
    {
      name         = "tenant-internal"
      memory_limit = "8Gi"
      cpu_limit    = "4"
      gpu_limit    = "1"
    },
    {
      name         = "tenant-customer-01"
      memory_limit = "4Gi"
      cpu_limit    = "2"
      gpu_limit    = "0"
    }
  ]
}
