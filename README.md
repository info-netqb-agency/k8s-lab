# k8s-lab

A portable, reproducible **local Kubernetes lab** (kind, 1 control-plane + 3
workers) deployed entirely with **Terraform**, at $0.

- **Terraform owns the platform** (`terraform/`): kind cluster, Cilium CNI,
  Traefik ingress, metrics-server, Argo CD, and one Argo CD `Application`.
- **Git owns the workloads**: Argo CD deploys `charts/hello` from this repo.
  Terraform does not touch it after the hand-off.

| Component        | Pin                                                                 |
| ---------------- | ------------------------------------------------------------------- |
| Terraform        | `1.17.0` (`>= 1.9`)                                                  |
| tehcyx/kind      | provider `0.13.0`                                                    |
| hashicorp/helm   | provider `~> 2.17` (3.x changed the block syntax)                    |
| Kubernetes nodes | `kindest/node:v1.36.1` (digest-pinned)                              |
| Cilium           | chart `1.20.4`                                                       |
| Traefik          | chart `42.1.3` (Traefik v3.7.16)                                     |
| metrics-server   | chart `3.13.1` (`--kubelet-insecure-tls`)                            |
| Argo CD          | chart `10.11.6` (v3.5.6); argocd-apps chart `2.0.7`                  |
| kubectl          | `v1.36.1`                                                            |
| demo app         | `hashicorp/http-echo:0.2.3`                                          |
| dashboard (opt.) | Headlamp chart `0.43.0`                                              |
| local AI (opt.)  | `ollama/ollama:0.31.1` + `open-webui:v0.10.2` (Docker + GPU)         |

---

## Prerequisites

- **Windows + Docker Desktop with WSL2 integration**, Docker running. Work
  inside your **WSL2 distro**.
- **RAM:** give Docker **>= 8 GB** (4 nodes + Cilium + Argo CD need ~5-6 GB;
  check `docker info --format '{{.MemTotal}}'`).
- **cgroup v2** (Kubernetes >= 1.35): `docker info --format '{{.CgroupVersion}}'`
  must print `2`. Otherwise see `docs/wslconfig-cgroupv2.txt`.
- `make install-tools` (or `./lab install-tools`) installs terraform, kubectl,
  kind and helm into `~/.local/bin` - no sudo.
- **A Git remote Argo CD can reach** (see below).

> **`make` is optional.** Every `make <target>` has an identical `./lab <target>`.

## Host ports

Traefik is published on **28080 (HTTP) / 28443 (HTTPS)** instead of 80/443 so
the lab never collides with other local services. Change them with
`-var http_port=... -var https_port=...` (also update `HTTP_PORT` in
`scripts/lib.sh` if you use the helper scripts).

| URL                                   | What                   |
| ------------------------------------- | ---------------------- |
| `http://hello.localhost:28080`        | demo app (via Argo CD) |
| `http://argocd.localtest.me:28080`    | Argo CD UI             |

`*.localhost` and `*.localtest.me` resolve to 127.0.0.1 - no hosts file edits.

## The GitOps remote

Argo CD runs *inside* the cluster, so it clones `charts/hello` over the network:
push this repo to a **public** GitHub/GitLab remote and tell Terraform:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # git-ignored
# edit hello_repo_url = "https://github.com/<you>/k8s-lab.git"
```

Until `hello_repo_url` points at a reachable repo, the `hello` Application shows
a sync error (everything else still works).

## Bring everything up

```bash
make install-tools   # once
make up              # terraform init + apply (~5-8 min first run)
export KUBECONFIG=~/.kube/k8s-lab.config   # printed by `make up`; also: make kubeconfig
make status          # nodes, pods, Argo CD apps
```

`make down` runs `terraform destroy`; `make reset` is down + up. State lives in
`terraform/terraform.tfstate` (git-ignored); the provider lock file
`terraform/.terraform.lock.hcl` is committed.

Knobs (`terraform/variables.tf`): `worker_count` (default 3), `cni`
(`cilium` | `kindnet`), `http_port`, `https_port`, `hello_repo_url`.
Example: `cd terraform && terraform apply -var worker_count=1 -var cni=kindnet`.
With Cilium the cluster is created with `disable_default_cni = true` and
`wait_for_ready = false` (nodes become Ready only after Cilium installs).

## Verify

```bash
kubectl get nodes                      # 1 control-plane + 3 workers, Ready
kubectl -n argocd get applications     # hello: Synced / Healthy
curl http://hello.localhost:28080      # -> Hello from k8s-lab
curl -I http://argocd.localtest.me:28080
kubectl top nodes
```

Argo CD admin password:
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

## CI (Azure DevOps)

`azure-pipelines.yml` runs on a Microsoft-hosted `ubuntu-latest` agent: install
Terraform -> init -> `fmt -check` -> validate -> apply -> smoke test (nodes
Ready, Argo app Healthy, curl hello/argocd) -> destroy (`condition: always()`).
No service connections or cloud resources, so it costs nothing. Set the pipeline
variable `HELLO_REPO_URL` to a public clone URL of this repo.

---

## Usage metrics

metrics-server is installed by Terraform, so `kubectl top nodes` / `kubectl top pods -A`
work ~30 s after `make up`. It runs with `--kubelet-insecure-tls` (kind kubelets use
self-signed certs) - fine for a lab, not for production.

## Web dashboard (Headlamp)

You can administer the cluster from a browser instead of the CLI. `make dashboard`
installs [Headlamp](https://headlamp.dev) via Helm and exposes it through the same
Traefik ingress at **http://dashboard.localhost:28080**:

```bash
make dashboard              # or: ./lab dashboard
```

It prints a 24-hour login token at the end. Open **http://dashboard.localhost:28080**,
choose token auth, and paste it. Reprint a token any time:

```bash
make dashboard-token        # or: ./lab dashboard-token
```

Remove it with `make undeploy-dashboard`. The login identity is a
`cluster-admin`-bound ServiceAccount (`dashboard/admin.yaml`) — convenient for a
local lab; don't reuse that binding on a real cluster.

> Prefer a terminal UI or a desktop app? `k9s` (TUI) and Lens/OpenLens (desktop,
> just point it at `~/.kube/config`) both work without installing anything in the
> cluster.

## Local AI (Ollama + Open WebUI, GPU)

Run local LLMs on the box's **NVIDIA GPU**. This stack runs on **Docker directly**
(not inside kind) so it can use the GPU via Docker's nvidia runtime — kind's node
containers can't see the GPU without extra device-plugin plumbing.

```bash
make ai-up                      # or: ./lab ai-up   -> starts Ollama + Open WebUI
make ai-pull                    # pull the default model (llama3.2:3b)
make ai-pull MODEL=qwen2.5:3b   # ...or any Ollama model
```

Then open **http://localhost:3000** (Open WebUI) and pick the model, or hit the
API directly:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"hello","stream":false}'
```

Inspect / stop:

```bash
make ai-status                  # containers + downloaded models + GPU usage
make ai-down                    # stop (downloaded models are kept in a volume)
```

**GPU sizing:** a 4 GB card (e.g. Quadro T2000) runs a 3B model fully on-GPU
(~40+ tok/s). 7–8B models spill to CPU and get slower; stick to ~3B for snappy
local chat. Models live in the `k8s-lab-ai_ollama` Docker volume and persist
across `ai-down`/`ai-up`. Open WebUI runs with `WEBUI_AUTH=false` (no login) for a
single-user local lab — remove that env in `ai/docker-compose.yml` to enable auth.

## Tear it all down

```bash
make undeploy-dashboard     # remove the Headlamp dashboard
make ai-down                # stop the local AI stack (models kept)
make stop                   # stop the cluster but KEEP it (state preserved)
make start                  # start a previously stopped cluster
make down                   # terraform destroy: delete the whole lab
make reset                  # delete + recreate from scratch
```

**Stop vs down:** `make stop` halts the node containers without deleting them
(via `docker stop`), so all cluster state is preserved and it stays down across
Docker/host restarts until `make start`. `make down` deletes the cluster
entirely. Use `stop`/`start` to park the cluster when you're not using it.

**Manual start only:** the cluster's node containers are set to `restart=no`
(applied by `make up`), so the cluster **never auto-starts** when Docker Desktop
or Windows restarts — it comes up only when you run `make up` / `make start`.

`make down` destroys everything cleanly; `make up` recreates it identically from
`terraform/`. The installed CLIs in `~/.local/bin` are left in place.

---

## What's in here

```
k8s-lab/
├── terraform/                  # platform: kind, Cilium, Traefik, metrics-server, Argo CD
│   ├── versions.tf  variables.tf  main.tf  outputs.tf
│   ├── terraform.tfvars.example
│   └── .terraform.lock.hcl     # committed
├── azure-pipelines.yml         # CI: apply -> smoke test -> destroy (always)
├── Makefile                    # make targets (thin wrappers over scripts/)
├── lab                         # same targets without make (./lab <target>)
├── dashboard/                  # Headlamp web UI (optional)
├── ai/docker-compose.yml       # Ollama + Open WebUI on Docker with GPU (optional)
├── scripts/                    # up/down (Terraform), stop/start, dashboard, ai, helpers
└── charts/hello/               # workload deployed by Argo CD, not by Terraform
```

All targets are **idempotent**: `up` reconciles in place and `down` is a no-op when
nothing is running.

---

## Notes & troubleshooting

- **Port 28080/28443 in use?** Pick others: `terraform apply -var http_port=... -var https_port=...`.
- **`hello` Application shows ComparisonError?** `hello_repo_url` is still the
  placeholder or the repo is private/unpushed. Set it in `terraform/terraform.tfvars`
  and `make up` again.
- **`terraform`/`kind`/`helm` "command not found"?** They live in `~/.local/bin`:
  `export PATH="$HOME/.local/bin:$PATH"`.
- **Nodes NotReady right after apply?** Cilium is still rolling out; give it a minute.
