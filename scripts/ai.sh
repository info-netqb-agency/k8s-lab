#!/usr/bin/env bash
# Local AI stack (Ollama + Open WebUI) on Docker with GPU. Usage: ai.sh <cmd> [arg]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "${ROOT_DIR}"

COMPOSE=(docker compose -f ai/docker-compose.yml)
OLLAMA_CTR="k8s-lab-ollama"
DEFAULT_MODEL="llama3.2:3b"   # ~2 GB, fits the T2000's 4 GB VRAM comfortably

cmd="${1:-help}"
case "${cmd}" in
  up)
    require_docker
    log "starting Ollama + Open WebUI (GPU) via docker compose"
    "${COMPOSE[@]}" up -d
    ok "AI stack up"
    cat <<EOF

  Chat UI    : http://localhost:3000     (Open WebUI)
  Ollama API : http://localhost:11434
Next, pull a model:
  make ai-pull                    # default: ${DEFAULT_MODEL}
  make ai-pull MODEL=qwen2.5:3b   # or any ollama model
EOF
    ;;
  down)
    require_docker
    log "stopping AI stack (models kept in the 'ollama' volume)"
    "${COMPOSE[@]}" down
    ok "AI stack stopped"
    ;;
  pull)
    require_docker
    model="${2:-${DEFAULT_MODEL}}"
    docker ps --format '{{.Names}}' | grep -qx "${OLLAMA_CTR}" || die "ollama not running — run 'make ai-up' first"
    log "pulling model '${model}' (first time downloads a few GB)"
    docker exec "${OLLAMA_CTR}" ollama pull "${model}"
    ok "model '${model}' ready — pick it in Open WebUI's model dropdown"
    ;;
  status)
    require_docker
    "${COMPOSE[@]}" ps
    echo
    log "models available in Ollama"
    docker exec "${OLLAMA_CTR}" ollama list 2>/dev/null || warn "ollama container not running (make ai-up)"
    echo
    log "GPU usage"
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null \
      || warn "nvidia-smi unavailable on host"
    ;;
  logs)
    require_docker
    "${COMPOSE[@]}" logs --tail=60
    ;;
  *)
    cat <<EOF
AI stack (Ollama + Open WebUI, Docker + GPU). Targets:
  ai-up            start the stack (GPU-accelerated)
  ai-down          stop the stack (models kept in a docker volume)
  ai-pull [MODEL]  pull a model (default ${DEFAULT_MODEL})
  ai-status        containers + models + GPU usage
  ai-logs          tail container logs
EOF
    ;;
esac
