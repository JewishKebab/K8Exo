output "argocd_admin_password_cmd" {
  description = "Command to get the ArgoCD initial admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_url" {
  description = "Port-forward command to access ArgoCD UI"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "tenant_namespaces" {
  description = "Created tenant namespaces"
  value       = [for t in var.tenants : t.name]
}

output "platform_namespace" {
  description = "Platform namespace"
  value       = kubernetes_namespace.platform.metadata[0].name
}
