#!/usr/bin/env python3
"""k8s-lab console: a small local web UI to build, inspect and tear down the lab.

Standard library only. Binds to 127.0.0.1. It runs a fixed whitelist of actions
(see ACTIONS), never arbitrary commands, and every state-changing request needs
the per-process token embedded in the page plus a localhost Host header.

    python3 console/server.py        # then open http://localhost:28900
"""
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATIC = Path(__file__).resolve().parent / "static"
PORT = int(os.environ.get("CONSOLE_PORT", "28900"))
CLUSTER = os.environ.get("CLUSTER_NAME", "k8s-lab")
INGRESS_PORT = int(os.environ.get("HTTP_PORT", "28080"))
KUBECONFIG = os.path.expanduser(os.environ.get("KUBECONFIG_PATH", "~/.kube/k8s-lab.config"))
TFVARS = ROOT / "terraform" / "terraform.tfvars"
TOKEN = secrets.token_urlsafe(24)
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
ENV = {
    **os.environ,
    "KUBECONFIG": KUBECONFIG,
    "PATH": os.path.expanduser("~/.local/bin") + os.pathsep + os.environ.get("PATH", ""),
    "NO_COLOR": "1",
    "TF_IN_AUTOMATION": "1",
}

# name -> (label, command). The only things this server will ever execute.
ACTIONS = {
    "up": ("Build lab", ["make", "up"]),
    "plan": ("Preview changes", ["bash", "-c", "cd terraform && terraform init -input=false -no-color >/dev/null && terraform plan -input=false -no-color"]),
    "down": ("Destroy lab", ["make", "down"]),
    "reset": ("Rebuild from scratch", ["make", "reset"]),
    "stop": ("Stop cluster", ["make", "stop"]),
    "start": ("Start cluster", ["make", "start"]),
    "refresh-hello": ("Refresh hello app", ["kubectl", "-n", "argocd", "annotate", "application", "hello",
                                              "argocd.argoproj.io/refresh=hard", "--overwrite"]),
}


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV, cwd=ROOT)
        return p.returncode, p.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return 1, ""


def kjson(args):
    rc, out = run(["kubectl", "--request-timeout=6s", *args, "-o", "json"], 12)
    try:
        return json.loads(out) if rc == 0 else None
    except ValueError:
        return None


# ---------------------------------------------------------------- jobs
class Job:
    def __init__(self, name, cmd):
        self.id = secrets.token_hex(4)
        self.name, self.label = name, ACTIONS[name][0] if name in ACTIONS else name
        self.lines, self.rc, self.started, self.ended = [], None, time.time(), None
        self.cond = threading.Condition()
        self.proc = subprocess.Popen(cmd, cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, bufsize=1, start_new_session=True)
        threading.Thread(target=self._pump, daemon=True).start()

    def _push(self, text):
        with self.cond:
            self.lines.append(text)
            self.cond.notify_all()

    def _pump(self):
        self._push(f"$ {self.label}")
        for line in self.proc.stdout:
            self._push(ANSI.sub("", line.rstrip("\n")))
        self.rc = self.proc.wait()
        self.ended = time.time()
        self._push(f"-- finished with exit code {self.rc}" if self.rc == 0 else f"-- failed with exit code {self.rc}")
        with self.cond:
            self.cond.notify_all()

    @property
    def running(self):
        return self.rc is None

    def meta(self):
        return {"id": self.id, "name": self.name, "label": self.label, "running": self.running, "rc": self.rc,
                "started": self.started, "ended": self.ended}


JOB = None
JOB_LOCK = threading.Lock()


def start_job(name, cmd=None):
    global JOB
    with JOB_LOCK:
        if JOB and JOB.running:
            return None
        JOB = Job(name, cmd or ACTIONS[name][1])
        return JOB


# ---------------------------------------------------------------- state
_cache = {"t": 0, "v": None}
_cache_lock = threading.Lock()


def docker_state():
    rc, out = run(["docker", "ps", "-a", "--filter", f"label=io.x-k8s.kind.cluster={CLUSTER}", "--format", "{{.State}}"], 8)
    states = out.split()
    if rc != 0:
        return "unknown"
    if not states:
        return "absent"
    if all(s == "running" for s in states):
        return "running"
    return "stopped" if all(s == "exited" for s in states) else "partial"


def pod_status(p):
    if p["metadata"].get("deletionTimestamp"):
        return "Terminating"
    st = p.get("status", {})
    for c in st.get("initContainerStatuses", []) + st.get("containerStatuses", []):
        w = (c.get("state") or {}).get("waiting")
        if w and w.get("reason") not in (None, "PodInitializing", "ContainerCreating"):
            return w["reason"]
    phase = st.get("phase", "Unknown")
    if phase == "Running":
        cs = st.get("containerStatuses", [])
        return "Running" if cs and all(c.get("ready") for c in cs) else "NotReady"
    return phase


def probe(host):
    req = urllib.request.Request(f"http://127.0.0.1:{INGRESS_PORT}/", headers={"Host": host})
    try:
        with urllib.request.urlopen(req, timeout=2) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def read_repo():
    if TFVARS.exists():
        m = re.search(r'^\s*hello_repo_url\s*=\s*"([^"]*)"', TFVARS.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1)
    return ""


def collect():
    cluster = docker_state()
    st = {"cluster": cluster, "time": time.time(), "nodes": [], "pods": [], "apps": [], "probes": {},
          "repo": read_repo(), "ingressPort": INGRESS_PORT, "kubeconfig": KUBECONFIG, "job": JOB.meta() if JOB else None}
    if cluster != "running":
        return st
    nodes, pods, apps = kjson(["get", "nodes"]), kjson(["get", "pods", "-A"]), kjson(["-n", "argocd", "get", "applications.argoproj.io"])
    top = {}
    rc, out = run(["kubectl", "--request-timeout=6s", "top", "nodes", "--no-headers"], 10)
    if rc == 0:
        for line in out.splitlines():
            f = line.split()
            if len(f) >= 5:
                top[f[0]] = {"cpuM": int(f[1].rstrip("m")) if f[1].endswith("m") else int(float(f[1]) * 1000),
                             "cpuPct": int(f[2].rstrip("%")), "memMi": int(f[3].rstrip("Mi")), "memPct": int(f[4].rstrip("%"))}
    for n in (nodes or {}).get("items", []):
        labels = n["metadata"].get("labels", {})
        ready = next((c["status"] == "True" for c in n["status"]["conditions"] if c["type"] == "Ready"), False)
        st["nodes"].append({"name": n["metadata"]["name"], "ready": ready, "version": n["status"]["nodeInfo"]["kubeletVersion"],
                            "role": "control-plane" if "node-role.kubernetes.io/control-plane" in labels else "worker",
                            "ip": next((a["address"] for a in n["status"]["addresses"] if a["type"] == "InternalIP"), ""),
                            "top": top.get(n["metadata"]["name"])})
    for p in (pods or {}).get("items", []):
        cs = p.get("status", {}).get("containerStatuses", [])
        st["pods"].append({"ns": p["metadata"]["namespace"], "name": p["metadata"]["name"], "node": p["spec"].get("nodeName", ""),
                           "status": pod_status(p), "restarts": sum(c.get("restartCount", 0) for c in cs),
                           "ready": f"{sum(1 for c in cs if c.get('ready'))}/{len(p['spec'].get('containers', []))}"})
    for a in (apps or {}).get("items", []):
        s, spec = a.get("status", {}), a.get("spec", {}).get("source", {})
        cond = (s.get("conditions") or [{}])[0].get("message", "")
        st["apps"].append({"name": a["metadata"]["name"], "sync": s.get("sync", {}).get("status", "Unknown"),
                           "health": s.get("health", {}).get("status", "Unknown"), "repo": spec.get("repoURL", ""),
                           "path": spec.get("path", ""), "revision": spec.get("targetRevision", ""), "message": cond[:300]})
    st["probes"] = {"hello": probe("hello.localhost"), "argocd": probe("argocd.localtest.me")}
    return st


def state():
    with _cache_lock:
        if time.time() - _cache["t"] > 2.5 or _cache["v"] is None:
            _cache["v"], _cache["t"] = collect(), time.time()
        v = _cache["v"]
    v["job"] = JOB.meta() if JOB else None
    return v


def invalidate():
    _cache["t"] = 0


REPO_RE = re.compile(r"^https://[A-Za-z0-9.-]+/[A-Za-z0-9._~/-]+$")


def save_repo(url):
    if not REPO_RE.match(url) or "CHANGE-ME" in url:
        return False
    text = TFVARS.read_text(encoding="utf-8") if TFVARS.exists() else ""
    line = f'hello_repo_url = "{url}"'
    if re.search(r"^\s*hello_repo_url\s*=", text, re.M):
        text = re.sub(r"^\s*hello_repo_url\s*=.*$", line, text, flags=re.M)
    else:
        text = (text.rstrip("\n") + "\n" if text else "") + line + "\n"
    TFVARS.write_text(text, encoding="utf-8", newline="\n")
    return True


# ---------------------------------------------------------------- http
class Handler(BaseHTTPRequestHandler):
    server_version = "k8s-lab-console"

    def log_message(self, *a):
        pass

    def _host_ok(self):
        return (self.headers.get("Host") or "").split(":")[0] in ("localhost", "127.0.0.1")

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self._host_ok():
            return self._send(403, {"error": "bad host"})
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            html = (STATIC / "index.html").read_text(encoding="utf-8").replace("__TOKEN__", TOKEN)
            return self._send(200, html.encode(), "text/html; charset=utf-8")
        if path == "/api/state":
            return self._send(200, state())
        m = re.fullmatch(r"/api/job/([0-9a-f]+)/stream", path)
        if m and JOB and JOB.id == m.group(1):
            return self._stream(JOB)
        self._send(404, {"error": "not found"})

    def _stream(self, job):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        i = 0
        try:
            while True:
                with job.cond:
                    while i >= len(job.lines) and job.running:
                        job.cond.wait(15)
                        if i >= len(job.lines) and job.running:
                            self.wfile.write(b": keepalive\n\n")
                            self.wfile.flush()
                    chunk, i = job.lines[i:], len(job.lines)
                    done = not job.running and i >= len(job.lines)
                for line in chunk:
                    self.wfile.write(b"data: " + json.dumps(line).encode() + b"\n\n")
                if done:
                    self.wfile.write(b"event: done\ndata: " + json.dumps(job.meta()).encode() + b"\n\n")
                    self.wfile.flush()
                    return
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return

    def do_POST(self):
        if not self._host_ok() or self.headers.get("X-Console-Token") != TOKEN:
            return self._send(403, {"error": "forbidden"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})
        path = self.path.split("?")[0]
        if path == "/api/action":
            name = body.get("name")
            if name == "cancel":
                if JOB and JOB.running:
                    os.killpg(os.getpgid(JOB.proc.pid), signal.SIGINT)
                    return self._send(200, {"ok": True})
                return self._send(409, {"error": "nothing running"})
            if name == "save-repo":
                ok = save_repo(str(body.get("url", "")).strip())
                invalidate()
                return self._send(200 if ok else 400, {"ok": ok, "error": None if ok else "Enter a public https:// repository URL."})
            if name not in ACTIONS:
                return self._send(400, {"error": "unknown action"})
            job = start_job(name)
            invalidate()
            return self._send(202, job.meta()) if job else self._send(409, {"error": "another job is running"})
        if path == "/api/secret/argocd":
            rc, out = run(["kubectl", "-n", "argocd", "get", "secret", "argocd-initial-admin-secret", "-o", "jsonpath={.data.password}"], 8)
            import base64
            return self._send(200, {"password": base64.b64decode(out).decode()} if rc == 0 and out else {"password": None})
        self._send(404, {"error": "not found"})


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"k8s-lab console: http://localhost:{PORT}   (Ctrl+C to stop)", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
        sys.exit(0)


if __name__ == "__main__":
    main()
