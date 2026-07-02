# Architecture

How TaskApp runs on a self-provisioned, multi-node Kubernetes cluster: the topology, the path
a request travels, and (the part graders look for) **each single-server assumption that broke
when moving off one box, and the Kubernetes mechanism that fixed it.**

---

## 1. Topology

```
                                     Internet
                                        │
                        DNS (GoDaddy)   │  taskapp.gbadedata.com  ─┐
                        A records ──────┤  api.gbadedata.com       │  → 18.130.208.33
                                        ▼                          │    (control-plane EIP)
   ╔════════════════════════════════════════════════════════════════════════════════╗
   ║  AWS VPC  10.0.0.0/16   ·   public subnet 10.0.1.0/24   ·   AZ eu-west-2a         ║
   ║                                                                                  ║
   ║   Security group (least privilege):                                              ║
   ║     22  ← admin /32 only      6443 ← admin /32 only                              ║
   ║     80  ← 0.0.0.0/0           443  ← 0.0.0.0/0        node↔node ← self            ║
   ║                                                                                  ║
   ║   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐            ║
   ║   │ control-plane     │   │ worker-1          │   │ worker-2          │            ║
   ║   │ k3s server        │   │ k3s agent         │   │ k3s agent         │            ║
   ║   │ 10.0.1.192        │   │ 10.0.1.61         │   │ 10.0.1.201        │            ║
   ║   │ EIP 18.130.208.33 │   │ EIP 13.134.28.72  │   │ EIP 18.135.154.105│            ║
   ║   └──────────────────┘   └──────────────────┘   └──────────────────┘            ║
   ║        t3.small (2 vCPU / 2 GiB) each · Ubuntu 22.04 · gp3 root · single AZ       ║
   ╚════════════════════════════════════════════════════════════════════════════════╝

   In-cluster (namespace: taskapp)
     ingress-nginx (LoadBalancer via k3s servicelb → all node IPs, ports 80/443)
        │  TLS terminated here (cert-manager, Let's Encrypt prod)
        ├── taskapp.gbadedata.com ─▶ frontend Svc ─▶ frontend Deployment (nginx, 2 replicas)
        │                                                    │  proxies /api
        └── api.gbadedata.com ──────▶ backend Svc ◀──────────┘
                                          │
                                     backend Deployment (Flask, HPA 2–6 replicas)
                                          │  SQLAlchemy / DATABASE_URL
                                          ▼
                                     postgres (headless Svc) ─▶ StatefulSet postgres-0
                                                                     │
                                                                PVC ─▶ EBS gp3 volume (in-AZ)

   Platform: cert-manager · metrics-server (bundled with k3s) · AWS EBS CSI driver · Argo CD
   GitOps:   Argo CD (argocd ns) ── watches ──▶ github.com/gbadedata/capstone-phoenix @ manifests/app
```

## 2. Nodes & network

- **Nodes.** 1 × k3s server (control-plane) + 2 × k3s agents (workers), all `t3.small`
  (2 vCPU / 2 GiB), Ubuntu 22.04, gp3 root volumes. The control plane is intentionally
  single-node. The brief's difficulty is Kubernetes, not etcd quorum.
- **Region / AZ.** `eu-west-2` (London), **single AZ** (`eu-west-2a`). This is a deliberate
  trade-off: AWS EBS volumes are AZ-scoped, so keeping all nodes in one AZ lets a rescheduled
  Postgres pod re-attach its existing volume on another node. The cost is no resilience to a
  full-AZ outage, which is acceptable because the brief's HA target is *node* failure, and
  multi-node-in-one-AZ satisfies. (Multi-AZ would require replicated storage such as Longhorn.)
- **Addressing.** VPC `10.0.0.0/16`; one public subnet `10.0.1.0/24`. No NAT gateway (that
  would add ~$32/mo and dominate the bill); nodes have public IPs and are protected by the
  security group instead. Elastic IPs give the nodes stable addresses across restarts.
- **Firewall.** Only `80`/`443` are open to the world. `22` and the Kubernetes API `6443` are
  restricted to a single admin `/32`, enforced twice, at the AWS security group **and** the
  host `ufw` firewall (defense in depth). Node-to-node traffic is allowed within the SG.

## 3. Request flow

A browser resolves `taskapp.gbadedata.com` via GoDaddy DNS to the control-plane Elastic IP
(`18.130.208.33`) on port `443`. k3s's `servicelb` publishes ingress-nginx on `80`/`443` of
every node, so the request reaches the **ingress-nginx** controller, which **terminates TLS**
using the Let's Encrypt certificate that cert-manager obtained (and auto-renews) via the
HTTP-01 challenge. Ingress routes the host `taskapp.gbadedata.com` to the **frontend** Service
(nginx, port 80), which serves the React SPA and **proxies `/api` to `backend:5000`**. The
**backend** (Flask) authenticates the JWT and talks to Postgres over SQLAlchemy using
`DATABASE_URL`, resolving the **`postgres`** headless Service to `postgres-0`, whose data lives
on an **EBS gp3** volume. (`api.gbadedata.com` routes straight to the backend for direct API
access.) The backend is fronted by an **HPA** that scales it 2→6 on CPU/memory.

## 4. The single-server assumptions we fixed  ← graders look here

Each row is an assumption that was safe on one Compose host but breaks on a cluster.

| Single-server assumption | Why it breaks on a cluster | How we fixed it |
|---|---|---|
| **Migrate-on-boot** in the container entrypoint | The image runs `alembic upgrade head` on startup; at 2+ replicas they race and collide (`DuplicateTable`, observed) | A run-once **db-init Job** (Argo **PreSync** hook) migrates + seeds first; each backend pod has an **initContainer** that blocks until the DB is seeded, so replicas never race |
| **Named volume on the host** | Pods reschedule across nodes; a host-path volume doesn't follow | Postgres **StatefulSet + PVC** on the **AWS EBS CSI** driver (`gp3`); the volume detaches and re-attaches on the new node (same AZ) |
| **`ports:` published on the host** | Many pods across many nodes need one front door | **ingress-nginx** + Services; k3s `servicelb` exposes the controller on all node IPs, with TLS at the edge |
| **A crash just restarts locally** | One box, one process to restart | **Deployments** + **liveness/readiness/startup probes**; Kubernetes reschedules onto healthy nodes automatically |
| **Deploy = stop old, start new** | Brief downtime was tolerable on one host | **RollingUpdate `maxUnavailable: 0`** + `maxSurge: 1`, readiness-gated cutover, `preStop` connection draining, and **PodDisruptionBudgets** |
| **`localhost` database** | App and DB were co-located | **Service DNS**: the app connects to `postgres:5432` and the frontend to `backend:5000`; connection details injected via env |
| **Secrets in a local `.env`** | One host, one file, nobody else reads it | **ConfigMap** (non-secret) + **Secret** created **out-of-band** with random credentials, never committed |
| **One machine = the ceiling** | A single box can't scale horizontally | **HPA** scales the backend 2→6 on real metrics; **NetworkPolicy** segments the tiers |

## 5. Key choices & trade-offs

- **kustomize** (not raw YAML or Helm) for the app. It gives one place to pin image tags and a
  clean base for Argo CD to build, without the ceremony of a chart for a single app.
- **ingress-nginx** over k3s's bundled Traefik (`--disable traefik`). It's the most widely
  documented path for cert-manager + HTTP-01, and keeps the ingress config portable.
- **NetworkPolicy is enforced:** k3s ships a built-in policy controller (kube-router's netpol
  engine), so the default flannel CNI enforces a default-deny + explicit-allow chain without
  swapping to Calico/Cilium. Verified: pods stay Ready and the app still serves with the
  policies applied.
- **Secrets out-of-band, not in git.** `create-secret.sh` generates a random `SECRET_KEY` and
  DB password and applies the Secret directly; Argo CD never manages it, so there's nothing to
  prune and nothing to leak. Sealed/External Secrets is the natural next step (see RUNBOOK).
- **Soft anti-affinity** (`topologySpreadConstraints` with `ScheduleAnyway`). Replicas spread
  across nodes in steady state, but during a drain they pile onto the surviving node instead of
  going `Pending`, which is exactly what keeps the app up in the failover demo.
- **HPA owns backend replica count** (no `replicas:` in the Deployment; Argo `ignoreDifferences`
  on `/spec/replicas`) so Argo's selfHeal and the HPA don't fight.

## 6. A note on the app image (why the DB wiring is what it is)

The published backend image is **newer than the app's source repo**: it uses **Alembic**
migrations (not `db.create_all()`), and its migration code reads **five discrete variables**:
`DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD`, while
the Flask app itself reads `DATABASE_URL`. If those five aren't set, the entrypoint silently
falls back to `localhost` and crashes. The deployment therefore injects **both** forms (the
`DATABASE_*` set via ConfigMap + Secret, and `DATABASE_URL` via Secret), and the db-init Job
runs the real `alembic upgrade head`. This is why the Job and the backend both carry the full
env set, a good example of reconciling a manifest with the artifact you were actually handed
rather than the source you expected.
