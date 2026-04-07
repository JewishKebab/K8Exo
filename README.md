# K8Exo

A self-hosted AI platform running entirely on your local machine — a Windows PC with WSL2 and an NVIDIA GPU. One command bootstraps a production-grade Kubernetes cluster with GPU support, GitOps, and a full suite of AI services.

---

## Table of Contents

1. [What We're Building](#what-were-building)
2. [Technology Breakdown](#technology-breakdown)
   - [WSL2](#wsl2)
   - [k3s](#k3s)
   - [Terraform](#terraform)
   - [Helm](#helm)
   - [ArgoCD](#argocd)
   - [Makefile](#makefile)
   - [Ollama](#ollama)
   - [Open WebUI](#open-webui)
   - [SearXNG](#searxng)
3. [Repo Structure](#repo-structure)
4. [How Deployment Works End-to-End](#how-deployment-works-end-to-end)
5. [Bootstrap](#bootstrap)
6. [Tenants](#tenants)
7. [Teardown](#teardown)

---

## What We're Building

Most AI tools (ChatGPT, Claude, etc.) run on someone else's servers. K8Exo lets you run the same class of AI infrastructure on your own hardware — privately, offline, and for free after the initial setup.

The stack gives you:
- A **Kubernetes cluster** running inside WSL2 on your Windows machine
- **Ollama** — runs large language models locally using your NVIDIA GPU (RTX 3060 12GB)
- **Open WebUI** — a polished chat UI connected to Ollama, with RAG, memory, and web search
- **SearXNG** — a self-hosted meta search engine that gives Open WebUI live web access
- Everything managed by **ArgoCD**, which keeps the cluster in sync with this Git repo automatically

---

## Technology Breakdown

### WSL2

**What it is:**
WSL2 (Windows Subsystem for Linux 2) is a full Linux kernel running inside Windows. It's deeply integrated with Windows, sharing the filesystem, networking, and GPU drivers.

**Why we use it:**
Kubernetes and most DevOps tooling is designed for Linux. WSL2 lets us run a real Linux environment on Windows without dual-booting. Critically, WSL2 also exposes the NVIDIA GPU to Linux processes via `/dev/dxg`, which allows Ollama to use the RTX 3060.

**What to know:**
- Your WSL filesystem lives at `\\wsl.localhost\Ubuntu\` in Windows Explorer
- Your Linux home directory is `~` inside WSL, which maps to `/home/<yourname>/`
- Always run cluster commands (`kubectl`, `terraform`, `make`) from a WSL terminal, not Windows CMD

---

### k3s

**What it is:**
k3s is a lightweight, production-ready distribution of Kubernetes made by Rancher. It strips out non-essentials and packages everything into a single binary under 100MB — perfect for a single local machine.

**Why we use it instead of Docker Desktop / minikube:**
- Closer to real production Kubernetes — skills transfer directly
- Better GPU passthrough support in WSL2
- Single binary, no daemon overhead

**How we install it:**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644" sh -
```
- `--disable traefik` — we manage ingress ourselves
- `--write-kubeconfig-mode 644` — makes kubeconfig readable without sudo

---

### Terraform

**What it is:**
Terraform is an Infrastructure-as-Code (IaC) tool. You describe the infrastructure you want in `.tf` files, and Terraform creates, updates, or deletes resources to match.

**Why we use it:**
Makes the entire bootstrap reproducible — delete everything and re-run `terraform apply` to get the exact same result.

**Providers used:**

| Provider | What it does |
|---|---|
| `kubernetes` | Creates namespaces, quotas, network policies in k3s |
| `helm` | Installs Helm charts (used to install ArgoCD) |
| `null` | Runs shell commands (installs k3s itself) |
| `local` | Reads local files |

**The deployment stages in `terraform/main.tf`:**

```
Stage 0: Install k3s
    └─> Stage 1: Wait for cluster ready
            └─> Create namespaces
                    └─> Apply ResourceQuotas + NetworkPolicies
            └─> Stage 3: Install ArgoCD via Helm
                    └─> Stage 4: Apply App-of-Apps manifest
```

---

### Helm

**What it is:**
Helm is the package manager for Kubernetes. A Helm chart is a collection of templated Kubernetes YAML files with default configuration values.

**How values work:**
Each chart has a `values.yaml` with defaults. We override specific values in our `helm-values/<service>/values.yaml` files. ArgoCD runs Helm internally — we never run `helm install` manually.

---

### ArgoCD

**What it is:**
ArgoCD is a GitOps continuous delivery tool for Kubernetes. It watches a Git repo and automatically applies any changes to the cluster.

**The App-of-Apps pattern:**
1. Terraform installs ArgoCD and applies one manifest: `gitops/bootstrap/argocd-app-of-apps.yaml`
2. This creates a single ArgoCD `Application` called `platform` that watches `gitops/platform/`
3. Every `.yaml` in `gitops/platform/` is itself an ArgoCD Application — one per service
4. ArgoCD reads those and deploys each service

Adding a new service = push a YAML to `gitops/platform/`. ArgoCD auto-syncs within ~3 minutes.

**Accessing ArgoCD:**
```bash
# Forward port
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

### Makefile

| Target | What it does |
|---|---|
| `make bootstrap` | Runs everything in order — the only command you need |
| `make install-terraform` | Downloads and installs Terraform |
| `make install-k3s` | Runs the k3s installer |
| `make kubeconfig` | Copies k3s kubeconfig to `~/.kube/config` |
| `make tf-init` | Runs `terraform init` |
| `make tf-apply` | Runs `terraform apply -auto-approve` |
| `make forward` | Sets up socat port-forwards (ArgoCD :8080, Open WebUI :3000, Ollama :11434) |
| `make destroy` | Tears down all Terraform-managed resources |

---

### Ollama

**What it is:**
Ollama downloads and runs large language models locally. It exposes a REST API on port `11434` — the local equivalent of the OpenAI API.

**GPU setup in WSL2:**
Standard Kubernetes GPU device plugins don't work in WSL2 because there are no `/dev/nvidia*` devices — the GPU is exposed via `/dev/dxg` (Windows WDDM driver). Instead we use:
- `nvidia-container-toolkit` installed in WSL2
- NVIDIA runtime registered in k3s containerd
- CDI (Container Device Interface) spec generated via `nvidia-ctk`
- `runtimeClassName: nvidia` on the Ollama pod
- `NVIDIA_VISIBLE_DEVICES=all` env var

This approach bypasses the device plugin entirely and works reliably in WSL2.

**Models running:**
- `llama3.2` — 3B general purpose model
- `llama3.1:8b` — 8B model, better quality (fits on 12GB VRAM)
- `nomic-embed-text` — embedding model for RAG

**Useful commands:**
```bash
# Check GPU is detected
kubectl logs deployment/ollama -n platform | grep "inference compute"

# List downloaded models
kubectl exec -n platform deploy/ollama -- ollama list

# Pull a new model
kubectl exec -it <ollama-pod> -n platform -- ollama pull <model>
```

---

### Open WebUI

**What it is:**
Open WebUI is a polished, self-hosted chat interface for Ollama. It supports multiple models, conversation history, RAG (document Q&A), memory, web search, and more.

**Why we replaced Dify:**
Dify was complex, resource-heavy, and unstable in this environment. Open WebUI is lightweight, works out of the box with Ollama, and has all the features we need.

**Deployment:** `gitops/platform/open-webui.yaml` → Helm chart from `helm.openwebui.com`

**Access:** `make forward` forwards it to `localhost:3000`

**Configuration:**
- Connects to Ollama at `http://ollama.platform.svc.cluster.local:11434`
- 10Gi persistent storage for chat history and uploaded documents
- Web search enabled, using SearXNG (see below)

**Admin password reset:**
```bash
# Get admin email
kubectl exec -it open-webui-0 -n platform -- python3 -c "
import sqlite3; conn = sqlite3.connect('/app/backend/data/webui.db')
print(conn.execute('SELECT email FROM user WHERE role=\"admin\"').fetchone())"

# Generate new bcrypt hash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'newpassword', bcrypt.gensalt()).decode())"

# Update password
kubectl exec -it open-webui-0 -n platform -- python3 -c "
import sqlite3; conn = sqlite3.connect('/app/backend/data/webui.db')
conn.execute(\"UPDATE auth SET password='<hash>' WHERE id=(SELECT id FROM user WHERE role='admin')\")
conn.commit()"
```

---

### SearXNG

**What it is:**
SearXNG is a self-hosted meta search engine that queries Google, Bing, DuckDuckGo and other engines simultaneously — no API keys required, no tracking.

**Why we use it:**
Open WebUI's built-in DuckDuckGo integration is rate-limited and unreliable. SearXNG runs inside the cluster and gives Open WebUI reliable web search for live data in chat.

**Deployment:** `manifests/searxng/deployment.yaml` — plain Kubernetes manifests (no Helm chart needed)

**WSL2 quirk:** Kubernetes injects a `SEARXNG_PORT` env var (as a full URL like `tcp://10.x.x.x:8080`) via service discovery, which SearXNG misinterprets as its port. Fixed with `enableServiceLinks: false` on the pod.

**Open WebUI config:**
In Admin Settings → Web Search → SearXNG URL:
```
http://searxng.platform.svc.cluster.local:8080
```

---

## Repo Structure

```
K8Exo/
│
├── Makefile                        # Single entry point: make bootstrap / make forward
│
├── terraform/                      # Bootstraps k3s + namespaces + ArgoCD
│   ├── providers.tf
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── helm-values/                    # Helm value overrides per service
│   ├── argocd/values.yaml
│   ├── ollama/values.yaml          # GPU config, models, storage
│   └── open-webui/values.yaml      # Ollama endpoint, storage
│
├── manifests/                      # Plain Kubernetes manifests (no Helm)
│   └── searxng/
│       └── deployment.yaml         # SearXNG deployment + configmap + service
│
└── gitops/                         # Everything ArgoCD manages after bootstrap
    ├── bootstrap/
    │   └── argocd-app-of-apps.yaml
    └── platform/                   # ArgoCD watches this — one file per service
        ├── ollama.yaml
        ├── open-webui.yaml
        └── searxng.yaml
```

---

## How Deployment Works End-to-End

```
1. You run: make bootstrap
       │
       ├─ install-terraform   → Downloads Terraform binary
       ├─ install-k3s         → Installs k3s, starts the cluster
       ├─ kubeconfig          → Copies k3s config, waits for node Ready
       ├─ tf-init             → Downloads Terraform providers
       └─ tf-apply            → Runs terraform apply:
              │
              ├─ Creates namespaces: platform, argocd, tenant-*
              ├─ Creates ResourceQuotas + NetworkPolicies
              ├─ Installs ArgoCD via Helm
              └─ Applies gitops/bootstrap/argocd-app-of-apps.yaml
                     │
                     └─ ArgoCD takes over:
                            │
                            └─ Watches gitops/platform/
                                   ├─ ollama.yaml     → Ollama (GPU inference)
                                   ├─ open-webui.yaml → Open WebUI (chat UI)
                                   └─ searxng.yaml    → SearXNG (web search)

2. From this point on:
   Adding a service = push a new YAML to gitops/platform/
   Changing config  = push updated values to helm-values/<service>/
   ArgoCD auto-syncs within ~3 minutes of every push.
```

---

## Bootstrap

Requirements:
- WSL2 with Ubuntu 22.04+
- NVIDIA drivers installed on Windows (shared automatically to WSL2)
- `nvidia-container-toolkit` installed in WSL2
- Internet access

```bash
cd ~/K8Exo && make bootstrap
```

After bootstrap, start port-forwards:
```bash
make forward
```

| Service | URL |
|---|---|
| Open WebUI | http://localhost:3000 |
| ArgoCD | http://localhost:8080 |
| Ollama API | http://localhost:11434 |

---

## Tenants

Two isolated namespaces are created by Terraform with hard resource limits:

| Namespace | Memory | CPU | GPU |
|---|---|---|---|
| `tenant-internal` | 8Gi | 4 cores | 1 |
| `tenant-customer-01` | 4Gi | 2 cores | 0 |

Each tenant has a `ResourceQuota` and a `NetworkPolicy` that default-denies all traffic with explicit egress to the `platform` namespace.

To add a tenant, edit the `tenants` variable in `terraform/variables.tf` and re-run `terraform apply`.

---

## Teardown

Remove all Terraform-managed resources:
```bash
make destroy
```

Fully uninstall k3s:
```bash
/usr/local/bin/k3s-uninstall.sh
```
