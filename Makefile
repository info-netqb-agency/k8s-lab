# k8s-lab — thin wrappers over scripts/. Requires GNU make.
# No make installed? Use the ./lab dispatcher — identical targets, zero deps.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help install-tools up down reset status ingress deploy-hello undeploy-hello dashboard dashboard-token undeploy-dashboard versions

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install-tools: ## Install kind/helm/kubectl if missing (user-local) + print versions
	@bash scripts/install-tools.sh

up: ## Create the 4-node kind cluster from kind-config.yaml
	@bash scripts/up.sh

down: ## Delete the kind cluster
	@bash scripts/down.sh

reset: ## Delete then recreate the cluster
	@bash scripts/reset.sh

status: ## Show nodes (-o wide) and all pods
	@bash scripts/status.sh

ingress: ## Install ingress-nginx and wait until ready
	@bash scripts/ingress.sh

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

versions: ## Print installed tool versions
	@bash -c 'source scripts/lib.sh; print_versions'
