# K8Exo

Local AI platform running on WSL2 + RTX 3060. One command bootstraps a full Kubernetes stack with GPU support, GitOps, and self-hosted AI services.

## Stack

| Layer | Tool |
|---|---|
| Kubernetes | k3s |
| GitOps | ArgoCD |
| AI inference | Ollama |
| Vector DB | Qdrant |
| AI workflow | Dify |
| Automation | n8n |
| GPU | NVIDIA GPU Operator |
| IaC | Terraform |

## Requirements

- WSL2 (Ubuntu 22.04+)
- NVIDIA RTX 3060 with drivers installed on Windows
- Internet access for downloads

## Bootstrap

Open a WSL terminal and run:

```bash
cd ~/K8Exo && make bootstrap
```

This will:
1. Install Terraform
2. Install k3s (single-node cluster, Traefik disabled)
3. Configure `~/.kube/config`
4. Run `terraform apply` — creates namespaces, resource quotas, network policies, installs ArgoCD
5. Apply the ArgoCD App-of-Apps — ArgoCD takes over and deploys the rest of the platform

## Accessing ArgoCD

After bootstrap completes, run the port-forward command printed in the output, then open `http://localhost:8080`.

To get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

## Repo Structure

```
K8Exo/
├── terraform/          # Bootstraps k3s, namespaces, ArgoCD
├── helm-values/        # Helm value overrides (ArgoCD, etc.)
├── gitops/
│   ├── bootstrap/      # ArgoCD App-of-Apps manifest
│   └── platform/       # Platform app definitions (managed by ArgoCD)
└── Makefile            # Single entry point: make bootstrap
```

## Tenants

Two tenant namespaces are created by default with resource quotas:

| Namespace | Memory | CPU | GPU |
|---|---|---|---|
| `tenant-internal` | 8Gi | 4 | 1 |
| `tenant-customer-01` | 4Gi | 2 | 0 |

Each tenant gets default-deny network policies with egress allowed to the `platform` namespace and DNS.

## Teardown

```bash
make destroy
```

This removes all Terraform-managed resources. To fully uninstall k3s:
```bash
/usr/local/bin/k3s-uninstall.sh
```
