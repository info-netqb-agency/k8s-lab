#!/usr/bin/env bash
# Destroy and recreate the cluster from scratch.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

log "reset: down then up"
bash "${HERE}/down.sh"
bash "${HERE}/up.sh"
