# k8s-lab — thin wrappers over scripts/. Requires GNU make.
# No make installed? Use the ./lab dispatcher — identical targets, zero deps.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: console help install-tools up down stop start reset status kubeconfig dashboard dashboard-token undeploy-dashboard ai-up ai-down ai-pull ai-status ai-logs versions

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install-tools: ## Install terraform/kind/helm/kubectl if missing (user-local) + print versions
	@bash scripts/install-tools.sh

up: ## terraform init + apply: cluster, Cilium, Traefik, metrics-server, Argo CD, hello app
	@bash scripts/up.sh

down: ## terraform destroy the whole lab
	@bash scripts/down.sh

stop: ## Stop the cluster's nodes without deleting it (state preserved)
	@bash scripts/stop.sh

start: ## Start a previously stopped cluster and wait until Ready
	@bash scripts/start.sh

reset: ## down then up
	@bash scripts/reset.sh

status: ## Show nodes (-o wide), all pods and Argo CD apps
	@bash scripts/status.sh

console: ## Open the browser console (buttons for build/destroy/status) at http://localhost:28900
	@python3 console/server.py

kubeconfig: ## Print the export command for the lab kubeconfig
	@echo "export KUBECONFIG=$${HOME}/.kube/k8s-lab.config"

undashboard: ## Install the Headlamp web UI at http://dashboard.localhost + print a login token
	@bash scripts/dashboard.sh

dashboard-token: ## Print a fresh 24h Headlamp login token
	@bash scripts/dashboard-token.sh

undeploy-dashboard: ## Remove the Headlamp web UI
	@bash scripts/undeploy-dashboard.sh

ai-up: ## Start the local AI stack (Ollama + Open WebUI, Docker + GPU) at localhost:3000
	@bash scripts/ai.sh up

ai-down: ## Stop the local AI stack (models are kept)
	@bash scripts/ai.sh down

ai-pull: ## Pull an Ollama model (default llama3.2:3b; override with MODEL=...)
	@bash scripts/ai.sh pull $(MODEL)

ai-status: ## Show AI containers, downloaded models, and GPU usage
	@bash scripts/ai.sh status

ai-logs: ## Tail the AI stack logs
	@bash scripts/ai.sh logs

versions: ## Print installed tool versions
	@bash -c 'source scripts/lib.sh; print_versions'
