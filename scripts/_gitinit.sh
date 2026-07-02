#!/usr/bin/env bash
set -euo pipefail
cd /mnt/d/kubernetes/k8s-lab
if [ ! -d .git ]; then
  git init -q
  echo "git: initialized"
else
  echo "git: already a repo"
fi
# Ensure a committer identity exists (local only) so the snapshot can be made.
git config user.email  >/dev/null 2>&1 || git config user.email "felix.zingel@netqb.online"
git config user.name   >/dev/null 2>&1 || git config user.name  "Felix Zingel"
# Mark shell entrypoints executable (best effort on DrvFs).
chmod +x lab scripts/*.sh 2>/dev/null || true
git add -A
if git diff --cached --quiet; then
  echo "git: nothing to commit"
else
  git commit -q -m "k8s-lab: reproducible 4-node kind cluster, ingress-nginx, hello Helm demo"
  echo "git: committed"
fi
echo "--- tree ---"
git ls-files | sed 's/^/  /'