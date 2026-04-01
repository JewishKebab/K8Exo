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
   - [Qdrant](#qdrant)
   - [Dify](#dify)
   - [n8n](#n8n)
   - [NVIDIA GPU Operator](#nvidia-gpu-operator)
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
- **Ollama** — runs large language models (LLMs) locally using your GPU
- **Qdrant** — a vector database for storing and searching AI embeddings (used for RAG / "chat with your documents")
- **Dify** — a UI and workflow engine to build AI apps on top of your models
- **n8n** — an automation tool to connect AI to external services (email, APIs, webhooks, etc.)
- Everything managed by **ArgoCD**, which keeps the cluster in sync with this Git repo automatically

---

## Technology Breakdown

### WSL2

**What it is:**
WSL2 (Windows Subsystem for Linux 2) is a full Linux kernel running inside Windows. It's not a virtual machine in the traditional sense — it's deeply integrated with Windows, sharing the filesystem, networking, and GPU drivers.

**Why we use it:**
Kubernetes and most DevOps tooling is designed for Linux. WSL2 lets us run a real Linux environment on Windows without dual-booting. Critically, WSL2 also exposes the NVIDIA GPU to Linux processes, which is what allows Ollama to use the RTX 3060.

**What to know:**
- Your WSL filesystem lives at `\\wsl.localhost\Ubuntu\` in Windows Explorer
- Your Linux home directory is `~` inside WSL, which maps to `/home/<yourname>/`
- Always run cluster commands (`kubectl`, `terraform`, `make`) from a WSL terminal, not Windows CMD

---

### k3s

**What it is:**
k3s is a lightweight, production-ready distribution of Kubernetes made by Rancher. Standard Kubernetes is designed for large cloud clusters and has a heavy footprint. k3s strips out the non-essentials and packages everything into a single binary under 100MB — perfect for a single local machine.

**Why we use it instead of Docker Desktop / minikube:**
- It's closer to real production Kubernetes — skills transfer directly
- Better GPU passthrough support
- Handles NVIDIA GPU Operator properly
- Single binary, no daemon overhead

**How we install it:**
The Makefile runs the official k3s install script with two flags:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644" sh -
```
- `--disable traefik` — k3s ships with the Traefik ingress controller by default. We disable it because we'll manage ingress ourselves.
- `--write-kubeconfig-mode 644` — makes the kubeconfig file readable without sudo, so tools like `kubectl` and `terraform` can use it as a normal user.

After install, k3s writes a kubeconfig to `/etc/rancher/k3s/k3s.yaml`. The Makefile copies this to `~/.kube/config`, which is the standard location every Kubernetes tool looks for by default.

---

### Terraform

**What it is:**
Terraform is an Infrastructure-as-Code (IaC) tool by HashiCorp. You describe the infrastructure you want in `.tf` files, and Terraform figures out how to create, update, or delete resources to match that description. This is called "declarative" configuration — you say *what* you want, not *how* to get there.

**Why we use it:**
Without Terraform, you'd manually run `kubectl create namespace`, install Helm charts by hand, and configure everything in an order you'd have to remember. Terraform makes the entire bootstrap reproducible — delete everything and re-run `terraform apply` to get the exact same result.

**How it works:**
Terraform has a concept of *providers* — plugins that know how to talk to specific APIs. We use four:

| Provider | What it does |
|---|---|
| `kubernetes` | Creates namespaces, quotas, network policies in k3s |
| `helm` | Installs Helm charts (we use it to install ArgoCD) |
| `null` | Runs shell commands (we use it to install k3s itself) |
| `local` | Reads local files |

**The deployment stages in `terraform/main.tf`:**

```
Stage 0: Install k3s (null_resource.k3s_install)
    └─> Stage 1: Wait for cluster ready (null_resource.k3s_ready)
            └─> Stage 1: Create namespaces (kubernetes_namespace)
                    └─> Stage 2: Apply ResourceQuotas (kubernetes_resource_quota)
                    └─> Stage 2: Apply NetworkPolicies (kubernetes_network_policy)
            └─> Stage 3: Install ArgoCD via Helm (helm_release.argocd)
                    └─> Stage 4: Apply App-of-Apps manifest (null_resource.argocd_app_of_apps)
```

Each resource has a `depends_on` that enforces this order. Terraform builds a dependency graph and runs independent resources in parallel where possible.

**Key files:**

- `terraform/providers.tf` — declares which providers to use and how to connect to the cluster
- `terraform/main.tf` — the actual infrastructure resources
- `terraform/variables.tf` — configurable inputs (tenant names, ArgoCD version, etc.)
- `terraform/outputs.tf` — values printed after `apply` (ArgoCD URL, password command)

---

### Helm

**What it is:**
Helm is the package manager for Kubernetes. A "Helm chart" is a collection of templated Kubernetes YAML files bundled together with default configuration values. Instead of writing 500 lines of YAML to deploy a complex app like ArgoCD, you run `helm install argocd argo/argo-cd` and Helm handles it.

**Why we use it:**
Every service in our stack (ArgoCD, Ollama, Qdrant, Dify, n8n) has an official or community Helm chart. Helm lets us customize deployments by overriding just the values we care about, without copying and maintaining the full YAML.

**How values work:**
Each chart has a `values.yaml` with defaults. We override specific values in our `helm-values/<service>/values.yaml` files. For example, to enable GPU support in Ollama we just set:
```yaml
ollama:
  gpu:
    enabled: true
    type: nvidia
    number: 1
```
Everything else uses the chart's defaults.

**How ArgoCD uses Helm:**
We don't run `helm install` manually. Instead, ArgoCD reads our `gitops/platform/*.yaml` Application manifests, sees that each one points to a Helm chart and our values file, and runs Helm internally to generate the Kubernetes manifests and apply them.

---

### ArgoCD

**What it is:**
ArgoCD is a GitOps continuous delivery tool for Kubernetes. "GitOps" means Git is the single source of truth for what should be running in the cluster. ArgoCD watches a Git repo and automatically applies any changes to the cluster.

**Why we use it:**
Without ArgoCD, adding a new service means manually running `helm install` or `kubectl apply`. With ArgoCD, you push a YAML file to Git and the cluster updates itself within minutes. It also continuously reconciles — if someone manually changes something in the cluster, ArgoCD reverts it back to match Git.

**How it works:**

1. Terraform installs ArgoCD into the `argocd` namespace via Helm
2. Terraform then applies one special manifest — `gitops/bootstrap/argocd-app-of-apps.yaml`
3. This creates a single ArgoCD `Application` called `platform` that watches the `gitops/platform/` folder in this repo
4. Every `.yaml` file in `gitops/platform/` is itself an ArgoCD `Application` — one per service
5. ArgoCD reads those and creates child apps (ollama, qdrant, dify, etc.), deploying each one

This "App of Apps" pattern means:
- Terraform only needs to bootstrap ArgoCD once
- After that, adding a new service = adding a YAML file to `gitops/platform/` and pushing to Git

**The App-of-Apps manifest explained:**
```yaml
# gitops/bootstrap/argocd-app-of-apps.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application           # This is an ArgoCD resource type
metadata:
  name: platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/JewishKebab/K8Exo  # Watch this repo
    targetRevision: HEAD                             # Always use the latest commit
    path: gitops/platform                            # Look in this folder
  destination:
    server: https://kubernetes.default.svc           # Deploy to the local cluster
    namespace: argocd
  syncPolicy:
    automated:
      prune: true       # Delete resources removed from Git
      selfHeal: true    # Revert manual changes in the cluster
```

**Accessing ArgoCD:**
ArgoCD runs inside the cluster with no external exposure by default. To access the UI, forward a local port to the ArgoCD service:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then open `http://localhost:8080`. Username: `admin`. Password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

### Makefile

**What it is:**
A `Makefile` is a file that defines named commands (called "targets") which can be run with `make <target>`. It's been around since 1976 and is available on every Unix/Linux system by default. Think of it as a scripting shortcut — instead of remembering and typing a sequence of commands, you define them once in the Makefile and run a single `make` command.

**Why we use it:**
The bootstrap process has a specific ordering problem: Terraform's `kubernetes` and `helm` providers need to connect to the cluster at plan time, but the cluster doesn't exist yet. The Makefile solves this by running k3s install and kubeconfig setup *before* invoking Terraform, so by the time Terraform runs, the cluster is already available.

**Our Makefile targets:**

| Target | What it does |
|---|---|
| `make bootstrap` | Runs everything in order — the only command you need |
| `make install-terraform` | Downloads and installs Terraform into `/usr/local/bin/` |
| `make install-k3s` | Runs the k3s installer (idempotent — skips if already installed) |
| `make kubeconfig` | Copies k3s kubeconfig to `~/.kube/config`, waits for node Ready |
| `make tf-init` | Runs `terraform init` — downloads providers |
| `make tf-apply` | Runs `terraform apply -auto-approve` |
| `make destroy` | Tears down all Terraform-managed resources |

**How targets chain together:**
```makefile
bootstrap: install-terraform install-k3s kubeconfig tf-init tf-apply
```
This line says: to run `bootstrap`, first run all five targets in order. Make handles the sequencing automatically.

---

### Ollama

**What it is:**
Ollama is a tool that makes it easy to download and run large language models (LLMs) locally. It wraps model management (downloading, versioning) and inference (running the model) behind a simple REST API on port `11434`. It's the local equivalent of the OpenAI API.

**Why we use it:**
Running models through OpenAI or Anthropic costs money and sends your data to third parties. Ollama lets you run open-source models (Llama 3, Mistral, Codellama, etc.) entirely on your own GPU — free, private, and offline.

**How we deploy it:**
ArgoCD reads `gitops/platform/ollama.yaml`, which points to the upstream Ollama Helm chart with our custom values from `helm-values/ollama/values.yaml`.

We use ArgoCD's **multi-source** feature — the chart comes from the Ollama Helm repository, but the values come from this Git repo. This keeps chart version management and our configuration cleanly separated.

**The ArgoCD Application manifest explained:**
```yaml
# gitops/platform/ollama.yaml

spec:
  sources:
    # Source 1: the upstream Helm chart
    - repoURL: https://otwld.github.io/ollama-helm/
      chart: ollama
      targetRevision: "0.58.0"     # Pinned chart version for reproducibility
      helm:
        valueFiles:
          - $values/helm-values/ollama/values.yaml  # $values refers to source 2 below

    # Source 2: this repo — used only to provide the values file above
    - repoURL: https://github.com/JewishKebab/K8Exo
      targetRevision: HEAD
      ref: values                  # Named reference used as $values above
```

**The values file explained:**
```yaml
# helm-values/ollama/values.yaml

ollama:
  gpu:
    enabled: true
    type: nvidia
    number: 1          # Use 1 GPU (our RTX 3060)
  models:
    - llama3.2         # Downloaded on startup — general purpose chat model
    - nomic-embed-text # Embedding model — used for Qdrant RAG ingestion

resources:
  limits:
    memory: "10Gi"           # Leave ~2GB headroom from the 12GB VRAM
    nvidia.com/gpu: "1"      # Kubernetes GPU resource request

persistentVolume:
  enabled: true
  size: 30Gi                 # Models are large — llama3.2 is ~2GB, others can be 7GB+
  storageClass: "local-path" # k3s built-in storage class (stores on local disk)

service:
  type: ClusterIP    # Only reachable inside the cluster — Dify/n8n talk to it internally
  port: 11434        # Ollama's default API port
```

**Useful commands after deployment:**
```bash
# Check it's running
kubectl get pods -n platform

# List downloaded models
kubectl exec -n platform deploy/ollama -- ollama list

# Run a quick test
kubectl exec -n platform deploy/ollama -- ollama run llama3.2 "explain kubernetes in one sentence"
```

---

### Qdrant

**What it is:**
Qdrant is a vector database. A "vector" is a list of numbers that represents the meaning of a piece of text (produced by an embedding model like `nomic-embed-text`). Qdrant stores these vectors and lets you search for semantically similar content — "find documents that mean the same thing as this query" — even if they don't share any exact words.

**Why we use it:**
This is the foundation of RAG (Retrieval-Augmented Generation) — the technique that lets an AI answer questions about your own documents. You embed your documents into Qdrant, then at query time you search Qdrant for relevant chunks and include them in the prompt sent to Ollama.

**Deployment:** Coming soon — will follow the same pattern as Ollama.

---

### Dify

**What it is:**
Dify is an open-source platform for building AI applications. It provides a visual UI to create chatbots, document Q&A apps, and AI workflows — connecting your models (Ollama), knowledge bases (Qdrant), and tools (APIs, databases) without writing code.

**Why we use it:**
Dify is the main user-facing layer of the stack. It connects to Ollama as its LLM backend and to Qdrant for knowledge retrieval. Instead of calling Ollama's API directly, users interact with Dify's chat UI or build workflows in its visual editor.

**Deployment:** Coming soon.

---

### n8n

**What it is:**
n8n is an open-source workflow automation tool — similar to Zapier or Make, but self-hosted. It connects to hundreds of services (Gmail, Slack, GitHub, HTTP APIs, databases) and lets you automate tasks with a visual node-based editor.

**Why we use it:**
n8n bridges the AI stack to the outside world. Example workflows:
- New email arrives → extract text → send to Ollama → summarize → reply
- GitHub issue created → analyze with LLM → auto-label and assign
- Schedule a daily report → pull data → run through AI → post to Slack

**Deployment:** Coming soon.

---

### NVIDIA GPU Operator

**What it is:**
The NVIDIA GPU Operator is a Kubernetes operator that automates everything needed to use NVIDIA GPUs inside a cluster: installing device plugins, drivers, container runtimes, and monitoring tools.

Without it, Kubernetes has no idea a GPU exists on the node. The GPU Operator registers the GPU as a schedulable resource (`nvidia.com/gpu: 1`) so pods can request it just like CPU or memory.

**Why we need it:**
When Ollama's pod spec says `nvidia.com/gpu: "1"`, Kubernetes needs something to:
1. Know that the GPU exists on the node
2. Inject the right devices and libraries into the container at runtime
3. Ensure only one pod uses the GPU at a time (when limit is 1)

The GPU Operator handles all of this automatically by running as a DaemonSet on every node.

**Deployment:** Coming soon.

---

## Repo Structure

```
K8Exo/
│
├── Makefile                        # Single entry point: make bootstrap
│
├── terraform/                      # Stage 0: bootstraps k3s + namespaces + ArgoCD
│   ├── providers.tf                # Provider config (kubernetes, helm, null, local)
│   ├── main.tf                     # Resources: k3s install, namespaces, quotas, ArgoCD
│   ├── variables.tf                # Inputs: tenant definitions, ArgoCD version
│   └── outputs.tf                  # Outputs: ArgoCD URL, admin password command
│
├── helm-values/                    # Helm value overrides per service
│   ├── argocd/
│   │   └── values.yaml             # ArgoCD config (insecure mode for local use)
│   └── ollama/
│       └── values.yaml             # Ollama config (GPU, models, storage)
│
└── gitops/                         # Everything ArgoCD manages after bootstrap
    ├── bootstrap/
    │   └── argocd-app-of-apps.yaml # The one manifest Terraform applies — seeds ArgoCD
    └── platform/                   # ArgoCD watches this folder — one file per service
        └── ollama.yaml             # Deploys Ollama into the platform namespace
```

---

## How Deployment Works End-to-End

```
1. You run: make bootstrap
       │
       ├─ install-terraform   → Downloads Terraform binary to /usr/local/bin/
       ├─ install-k3s         → Installs k3s, starts the cluster
       ├─ kubeconfig          → Copies k3s config to ~/.kube/config, waits for node Ready
       ├─ tf-init             → Downloads Terraform providers
       └─ tf-apply            → Runs terraform apply:
              │
              ├─ Creates namespaces: platform, argocd, tenant-internal, tenant-customer-01
              ├─ Creates ResourceQuotas per tenant (CPU, memory, GPU limits)
              ├─ Creates NetworkPolicies (default-deny + allow platform egress)
              ├─ Installs ArgoCD via Helm into argocd namespace
              └─ Applies gitops/bootstrap/argocd-app-of-apps.yaml
                     │
                     └─ ArgoCD takes over from here:
                            │
                            └─ Watches gitops/platform/ in this repo
                                   │
                                   ├─ Finds ollama.yaml  → deploys Ollama
                                   ├─ (soon) qdrant.yaml → deploys Qdrant
                                   ├─ (soon) dify.yaml   → deploys Dify
                                   └─ (soon) n8n.yaml    → deploys n8n

2. From this point on:
   Adding a service = push a new YAML to gitops/platform/
   Changing config  = push updated values to helm-values/<service>/
   ArgoCD auto-syncs within ~3 minutes of every push.
```

---

## Bootstrap

Requirements:
- WSL2 with Ubuntu 22.04+
- NVIDIA drivers installed on Windows (not inside WSL — Windows drivers are shared automatically)
- Internet access

```bash
cd ~/K8Exo && make bootstrap
```

---

## Tenants

Two isolated namespaces are created by Terraform with hard resource limits:

| Namespace | Memory | CPU | GPU |
|---|---|---|---|
| `tenant-internal` | 8Gi | 4 cores | 1 |
| `tenant-customer-01` | 4Gi | 2 cores | 0 |

Each tenant has:
- A `ResourceQuota` preventing runaway resource consumption
- A `NetworkPolicy` that default-denies all traffic, with explicit egress allowed to the `platform` namespace (where Ollama, Qdrant, etc. live) and DNS

To add a tenant, edit the `tenants` variable in `terraform/variables.tf` and re-run `terraform apply`.

---

## Teardown

Remove all Terraform-managed resources (namespaces, ArgoCD, quotas):
```bash
make destroy
```

Fully uninstall k3s from WSL:
```bash
/usr/local/bin/k3s-uninstall.sh
```
