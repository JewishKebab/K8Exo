# ─────────────────────────────────────────────
# Stage 0: Install k3s on local WSL2 machine
# ─────────────────────────────────────────────
resource "null_resource" "k3s_install" {
  provisioner "local-exec" {
    command = <<-EOT
      if ! command -v k3s &> /dev/null; then
        echo "Installing k3s..."
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
          --disable traefik \
          --write-kubeconfig-mode 644" sh -
        mkdir -p ~/.kube
        sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
        sudo chown $USER ~/.kube/config
        echo "k3s installed."
      else
        echo "k3s already installed, skipping."
      fi
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "k3s_ready" {
  depends_on = [null_resource.k3s_install]

  provisioner "local-exec" {
    command     = "kubectl wait --for=condition=Ready nodes --all --timeout=180s"
    interpreter = ["bash", "-c"]
  }
}

# ─────────────────────────────────────────────
# Stage 1: Core namespaces
# ─────────────────────────────────────────────
resource "kubernetes_namespace" "platform" {
  depends_on = [null_resource.k3s_ready]

  metadata {
    name = "platform"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  depends_on = [null_resource.k3s_ready]

  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "tenants" {
  for_each   = { for t in var.tenants : t.name => t }
  depends_on = [null_resource.k3s_ready]

  metadata {
    name = each.value.name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "k8exo/tenant"                 = each.value.name
    }
  }
}

# ─────────────────────────────────────────────
# Stage 2: ResourceQuotas per tenant
# ─────────────────────────────────────────────
resource "kubernetes_resource_quota" "tenant_quotas" {
  for_each   = { for t in var.tenants : t.name => t }
  depends_on = [kubernetes_namespace.tenants]

  metadata {
    name      = "quota"
    namespace = each.value.name
  }

  spec {
    hard = {
      "requests.memory"       = each.value.memory_limit
      "limits.memory"         = each.value.memory_limit
      "requests.cpu"          = each.value.cpu_limit
      "limits.cpu"            = each.value.cpu_limit
      "nvidia.com/gpu"        = each.value.gpu_limit
      "pods"                  = "20"
      "services"              = "10"
    }
  }
}

# ─────────────────────────────────────────────
# Stage 3: Default-deny NetworkPolicies
# ─────────────────────────────────────────────
resource "kubernetes_network_policy" "tenant_default_deny" {
  for_each   = { for t in var.tenants : t.name => t }
  depends_on = [kubernetes_namespace.tenants]

  metadata {
    name      = "default-deny-all"
    namespace = each.value.name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "tenant_allow_platform" {
  for_each   = { for t in var.tenants : t.name => t }
  depends_on = [kubernetes_namespace.tenants]

  metadata {
    name      = "allow-platform-egress"
    namespace = each.value.name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "platform"
          }
        }
      }
    }

    # Allow DNS
    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }
  }
}

# ─────────────────────────────────────────────
# Stage 4: Bootstrap ArgoCD via Helm
# ─────────────────────────────────────────────
resource "helm_release" "argocd" {
  depends_on = [kubernetes_namespace.argocd]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = "argocd"

  values = [file("${path.module}/../helm-values/argocd/values.yaml")]

  timeout = 600
}

# ─────────────────────────────────────────────
# Stage 5: Hand off to ArgoCD App-of-Apps
# ─────────────────────────────────────────────
resource "null_resource" "argocd_app_of_apps" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ArgoCD server..."
      kubectl wait --for=condition=Available deployment/argocd-server \
        -n argocd --timeout=300s
      echo "Applying App-of-Apps..."
      kubectl apply -f ${path.module}/../gitops/bootstrap/argocd-app-of-apps.yaml
      echo "Done — ArgoCD is managing the platform."
    EOT
    interpreter = ["bash", "-c"]
  }
}
