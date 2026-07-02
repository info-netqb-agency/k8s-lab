# k8s-lab — thin wrappers over scripts/. Requires GNU make.
# No make installed? Use the ./lab dispatcher — identical targets, zero deps.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help install-tools up down stop start reset status ingress metrics deploy-hello undeploy-hello dashboard dashboard-token undeploy-dashboard ai-up ai-down ai-pull ai-status ai-logs versions

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install-tools: ## Install kind/helm/kubectl if missing (user-local) + print versions
	@bash scripts/install-tools.sh

up: ## Create the 4-node kind cluster from kind-config.yaml
	@bash scripts/up.sh

down: ## Delete the kind cluster
	@bash scripts/down.sh

stop: ## Stop the cluster's nodes without deleting it (state preserved)
	@bash scripts/stop.sh

start: ## Start a previously stopped cluster and wait until Ready
	@bash scripts/start.sh

reset: ## Delete then recreate the cluster
	@bash scripts/reset.sh

status: ## Show nodes (-o wide) and all pods
	@bash scripts/status.sh

ingress: ## Install ingress-nginx and wait until ready
	@bash scripts/ingress.sh

metrics: ## Install metrics-server (enables kubectl top + Headlamp usage graphs)
	@bash scripts/metrics.sh

deploy-hello: ## Deploy the hello Helm chart
	@bash scripts/deploy-hello.sh

undeploy-hello: ## Remove the hello Helm chart
	@bash scripts/undeploy-hello.sh

dashboard: ## Install the Headlamp web UI at http://dashboard.localhost + print a login token
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
