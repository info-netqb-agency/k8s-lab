#!/usr/bin/env bash
# Install kubectl / kind / helm if missing (user-local, no sudo) and print versions.
# Detects what is already installed rather than reinstalling blindly.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
ensure_tools
echo
print_versions

case ":${PATH}:" in
  *":${BIN_DIR}:"*) : ;;
  *)
    warn "${BIN_DIR} is not on your PATH in this shell."
    warn "Add this line to ~/.bashrc so kind/helm persist across shells:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac
