# k8s-lab

A portable, reproducible **4-node local Kubernetes cluster** (kind) defined entirely
as code. Destroy and recreate it identically on any machine. Includes an
ingress-nginx controller and a minimal Helm demo app reachable at
`http://hello.localhost`.

Everything is pinned to exact versions:

| Component        | Pin                                                                 |
| ---------------- | ------------------------------------------------------------------- |
| kind (CLI)       | `v0.32.0`                                                            |
| Kubernetes nodes | `kindest/node:v1.34.8` (digest-pinned)                              |
| helm             | `v4.2.2`                                                             |
| kubectl          | `v1.34.1`                                                            |
| ingress-nginx    | `controller-v1.15.1` (vendored kind manifest)                       |
| metrics-server   | chart `3.13.1` / app `v0.8.1` (optional usage metrics)              |
| demo app         | `hashicorp/http-echo:0.2.3`                                          |
| dashboard        | Headlamp chart `0.43.0` (optional web UI)                            |

---

## Prerequisites

- **Windows + Docker Desktop with WSL2 integration**, Docker running.
- Run everything **inside your WSL2 distro** (e.g. Ubuntu).
- `curl` and `git` (present on a default Ubuntu WSL). `kubectl`, `kind` and
  `helm` are installed automatically if missing — into `~/.local/bin`, **no sudo**.
- Recommended: **≥ 4 GB** RAM allocated to Docker for 4 nodes (this repo was
  built against 16 GB — check with `docker info --format '{{.MemTotal}}'`).

> **`make` is optional.** If `make` isn't installed, use the bundled `./lab`
> dispatcher — every `make <target>` below has an identical `./lab <target>`.

---

## Bring everything up from zero

From the `k8s-lab/` directory, inside WSL2:

```bash
# 1. Install kind/helm/kubectl if missing, and print versions
make install-tools          # or: ./lab install-tools

# 2. Create the 4-node cluster (1 control-plane + 3 workers)
make up                     # or: ./lab up

# 3. Install the ingress controller and wait until it's ready
make ingress                # or: ./lab ingress

# 4. Deploy the demo app
make deploy-hello           # or: ./lab deploy-hello
```

One-liner:

```bash
make install-tools && make up && make ingress && make deploy-hello
```

---

## Verify each step

**Tools installed:**
```bash
make versions               # kubectl / kind / helm / docker versions
```

**Cluster is up (4 nodes Ready):**
```bash
make status                 # kubectl get nodes -o wide + get pods -A
```
Expect 1 `control-plane` + 3 `<none>` (worker) nodes, all `Ready`.

**Ingress controller ready:**
```bash
kubectl -n ingress-nginx get pods
```
The `ingress-nginx-controller-*` pod should be `Running` / `1/1`.

**Demo app reachable** (uses an explicit Host header, so no DNS setup needed):
```bash
curl -H 'Host: hello.localhost' http://localhost
# -> Hello from k8s-lab
```

---

## Reach the demo app from your browser

Open **http://hello.localhost**

`*.localhost` resolves to `127.0.0.1` automatically in Chrome/Edge/Firefox, and
the cluster publishes port 80 from the control-plane node to your host via
`extraPortMappings`, so it just works — no `hosts` file edits.

If a tool on your machine doesn't resolve `*.localhost`, add to your hosts file:
```
127.0.0.1  hello.localhost
```

---

## Usage metrics (metrics-server)

To get CPU/memory usage (`kubectl top` and the graphs in Headlamp):

```bash
make metrics                # or: ./lab metrics
kubectl top nodes
kubectl top pods -A
```

kind's kubelets use self-signed serving certs, so metrics-server is configured
with `--kubelet-insecure-tls` (see `metrics/values.yaml`) — appropriate for a
local lab, not for production. First readings appear ~15–30s after install.

## Web dashboard (Headlamp)

You can administer the cluster from a browser instead of the CLI. `make dashboard`
installs [Headlamp](https://headlamp.dev) via Helm and exposes it through the same
ingress at **http://dashboard.localhost**:

```bash
make dashboard              # or: ./lab dashboard
```

It prints a 24-hour login token at the end. Open **http://dashboard.localhost**,
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

## Tear it all down

```bash
make undeploy-hello         # remove just the demo app
make undeploy-dashboard     # remove the Headlamp dashboard
make down                   # delete the whole cluster
make reset                  # delete + recreate from scratch
```

`make down` destroys everything cleanly; `make up` recreates it identically from
`kind-config.yaml`. The installed CLIs in `~/.local/bin` are left in place.

---

## What's in here

```
k8s-lab/
├── kind-config.yaml            # 4-node cluster, pinned node image, ports 80/443
├── Makefile                    # make targets (thin wrappers over scripts/)
├── lab                         # same targets without make (./lab <target>)
├── manifests/
│   └── ingress-nginx-kind.yaml # vendored ingress-nginx (controller-v1.15.1)
├── dashboard/                  # Headlamp web UI (values + cluster-admin identity)
│   ├── values.yaml
│   └── admin.yaml
├── metrics/
│   └── values.yaml             # metrics-server (kind-friendly --kubelet-insecure-tls)
├── scripts/                    # the real logic — single source of truth
│   ├── lib.sh                  # pinned versions + shared helpers/installers
│   ├── install-tools.sh
│   ├── up.sh  down.sh  reset.sh  status.sh
│   ├── ingress.sh  metrics.sh
│   ├── deploy-hello.sh  undeploy-hello.sh
│   └── dashboard.sh  dashboard-token.sh  undeploy-dashboard.sh
└── charts/hello/               # minimal Helm chart (Deployment/Service/Ingress)
```

All targets are **idempotent** where it makes sense: `up` won't recreate an
existing cluster, `ingress`/`deploy-hello` reconcile in place, and `down` is a
no-op when nothing is running.

---

## Notes & troubleshooting

- **Ports 80/443 already in use on the host?** Another service (or a second kind
  cluster) is bound to them. Free them, or change the `hostPort`s in
  `kind-config.yaml` and re-run `make reset`.
- **`kind`/`helm` "command not found" in a new shell?** They live in
  `~/.local/bin`. Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`.
  (The scripts add it automatically at runtime.)
- **Upgrading the ingress version:** re-vendor `manifests/ingress-nginx-kind.yaml`
  from the desired `controller-vX.Y.Z` tag and commit it — that keeps the
  cluster reproducible regardless of upstream changes.
