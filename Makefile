SHELL        := /bin/bash
TF_VERSION   := 1.9.8
TF_BIN       := /usr/local/bin/terraform
TF_DIR       := $(CURDIR)/terraform

.PHONY: bootstrap install-terraform install-k3s kubeconfig tf-init tf-apply destroy \
        forward forward-stop forward-argocd forward-dify forward-dify-api forward-ollama forward-qdrant

## Single entry point — run this once to bring up the full stack
bootstrap: install-terraform install-k3s kubeconfig tf-init tf-apply
	@echo ""
	@echo "Bootstrap complete."
	@echo "  ArgoCD UI : http://localhost:8080  (run: kubectl port-forward svc/argocd-server -n argocd 8080:443)"
	@echo "  Admin pw  : $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

# ── Prerequisites ────────────────────────────────────────────────────────────

install-terraform:
	@if command -v terraform &>/dev/null; then \
		echo "terraform already installed ($$(terraform version | head -1))"; \
	else \
		echo "Installing Terraform $(TF_VERSION)..."; \
		curl -fsSL https://releases.hashicorp.com/terraform/$(TF_VERSION)/terraform_$(TF_VERSION)_linux_amd64.zip \
			-o /tmp/terraform.zip; \
		sudo unzip -q -o /tmp/terraform.zip -d /usr/local/bin/; \
		rm /tmp/terraform.zip; \
		echo "Installed: $$(terraform version | head -1)"; \
	fi

install-k3s:
	@if command -v k3s &>/dev/null; then \
		echo "k3s already installed, skipping."; \
	else \
		echo "Installing k3s..."; \
		curl -sfL https://get.k3s.io | \
			INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644" sh -; \
		echo "k3s installed."; \
	fi

# Sets up ~/.kube/config and blocks until the node is Ready.
# Must run before terraform so the kubernetes/helm providers can connect.
kubeconfig:
	@mkdir -p ~/.kube
	@if [ ! -f ~/.kube/config ]; then \
		echo "Copying kubeconfig..."; \
		sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config; \
		sudo chown $$USER ~/.kube/config; \
	fi
	@echo "Waiting for k3s node Ready (timeout 180s)..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=180s
	@echo "Cluster is up."

# ── Terraform ────────────────────────────────────────────────────────────────

tf-init:
	@cd $(TF_DIR) && terraform init -input=false

tf-apply:
	@cd $(TF_DIR) && terraform apply -input=false -auto-approve

# ── Port Forwards ────────────────────────────────────────────────────────────
# Ports:
#   8080  → ArgoCD UI
#   3000  → Dify Web (frontend)
#   5001  → Dify API (backend)
#   11434 → Ollama (LLM inference)
#   6333  → Qdrant (vector DB REST)

## Forward all services via socat (WSL2-compatible)
forward:
	@which socat >/dev/null 2>&1 || apt-get install -y socat
	@kill $$(pgrep -f "socat TCP-LISTEN") 2>/dev/null || true
	@sleep 1
	@socat TCP-LISTEN:3000,fork,reuseaddr TCP:$$(kubectl get svc dify-web-svc   -n platform -o jsonpath='{.spec.clusterIP}'):3000  &
	@socat TCP-LISTEN:5001,fork,reuseaddr TCP:$$(kubectl get svc dify-api-svc   -n platform -o jsonpath='{.spec.clusterIP}'):5001  &
	@socat TCP-LISTEN:8080,fork,reuseaddr TCP:$$(kubectl get svc argocd-server  -n argocd   -o jsonpath='{.spec.clusterIP}'):80    &
	@socat TCP-LISTEN:11434,fork,reuseaddr TCP:$$(kubectl get svc ollama        -n platform -o jsonpath='{.spec.clusterIP}'):11434 &
	@socat TCP-LISTEN:6333,fork,reuseaddr TCP:$$(kubectl get svc dify-qdrant    -n platform -o jsonpath='{.spec.clusterIP}'):6333  &
	@echo ""
	@echo "Services forwarded (background):"
	@echo "  ArgoCD   → http://localhost:8080"
	@echo "  Dify UI  → http://localhost:3000"
	@echo "  Dify API → http://localhost:5001"
	@echo "  Ollama   → http://localhost:11434"
	@echo "  Qdrant   → http://localhost:6333"
	@echo ""
	@echo "ArgoCD admin password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d && echo

## Kill all socat forwarders
forward-stop:
	@kill $$(pgrep -f "socat TCP-LISTEN") 2>/dev/null || true
	@echo "All port-forwards stopped."

forward-argocd:
	@socat TCP-LISTEN:8080,fork,reuseaddr TCP:$$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}'):80

forward-dify:
	@socat TCP-LISTEN:3000,fork,reuseaddr TCP:$$(kubectl get svc dify-web-svc -n platform -o jsonpath='{.spec.clusterIP}'):3000

forward-dify-api:
	@socat TCP-LISTEN:5001,fork,reuseaddr TCP:$$(kubectl get svc dify-api-svc -n platform -o jsonpath='{.spec.clusterIP}'):5001

forward-ollama:
	@socat TCP-LISTEN:11434,fork,reuseaddr TCP:$$(kubectl get svc ollama -n platform -o jsonpath='{.spec.clusterIP}'):11434

forward-qdrant:
	@socat TCP-LISTEN:6333,fork,reuseaddr TCP:$$(kubectl get svc dify-qdrant -n platform -o jsonpath='{.spec.clusterIP}'):6333

# Tear everything down (keeps k3s intact — run k3s-uninstall.sh separately)
destroy:
	@cd $(TF_DIR) && terraform destroy -input=false -auto-approve
