# Phoenix: TaskApp on a Self-Provisioned Kubernetes Cluster

Production-style deployment of a full-stack **TaskApp** (React/nginx + Flask/PostgreSQL) onto a
**multi-node k3s cluster provisioned from scratch on AWS**, highly available, autoscaling,
zero-downtime, behind HTTPS on a real domain, and reconciled entirely by **GitOps**.

![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Config-Ansible-EE0000?logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Orchestration-k3s-FFC61C?logo=kubernetes&logoColor=white)
![Argo CD](https://img.shields.io/badge/GitOps-Argo%20CD-EF7B4D?logo=argo&logoColor=white)
![cert-manager](https://img.shields.io/badge/TLS-Let's%20Encrypt-003A70?logo=letsencrypt&logoColor=white)
![AWS](https://img.shields.io/badge/Cloud-AWS%20eu--west--2-232F3E?logo=amazonaws&logoColor=white)

**Live:** https://taskapp.gbadedata.com &nbsp;·&nbsp; **API:** https://api.gbadedata.com/api

---

## What this is

A single server with Docker Compose is easy. The moment you need **high availability,
autoscaling, and zero-downtime deploys**, you need orchestration, and a pile of
single-machine assumptions quietly break. This project takes an app that ran on one box and
re-homes it on a real cluster, fixing each of those assumptions explicitly.

Everything is codified: **Terraform** builds the infrastructure, **Ansible** installs the
cluster, **Helm + manifests** deploy the platform and app, and **Argo CD** keeps the live
state continuously in sync with this repository. A teammate can reproduce the entire stack
from [`docs/RUNBOOK.md`](docs/RUNBOOK.md) without asking a single question.

## Architecture at a glance

```
                                   Internet
                                      │
                      DNS (GoDaddy)   │   taskapp.gbadedata.com
                      A → 18.130.208.33   api.gbadedata.com
                                      ▼
                    ┌─────────────────────────────────────┐
                    │   ingress-nginx   (on every node)    │  ← TLS terminated here
                    │   Let's Encrypt cert via cert-manager │     (HTTP-01 challenge)
                    └───────┬──────────────────────┬────────┘
              taskapp.­…/    │                      │   api.­…/
                            ▼                      ▼
                   ┌────────────────┐     ┌──────────────────┐
                   │  frontend Svc  │     │   backend Svc     │
                   │  nginx · 2 rep │──▶──│   backend:5000    │
                   │  proxies /api  │/api │   Flask · HPA 2–6 │
                   └────────────────┘     └────────┬─────────┘
                                                   │ SQLAlchemy
                                                   ▼
                                          ┌──────────────────┐
                                          │  postgres (svc)  │
                                          │  StatefulSet     │
                                          │  PVC → EBS gp3   │
                                          └──────────────────┘

   Nodes: single AZ, eu-west-2a          GitOps
   ┌───────────────┬──────────────┐       Argo CD ── watches ──▶ this repo
   │ control-plane │ 10.0.1.192   │       (manifests/app, auto-sync,
   │ worker-1      │ 10.0.1.61    │        prune + selfHeal)
   │ worker-2      │ 10.0.1.201   │
   └───────────────┴──────────────┘
```

Full detail (topology, request flow, and the single-server assumptions fixed) is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Tech stack

| Layer | Technology | Notes |
|---|---|---|
| Infrastructure | **Terraform** (modular, remote state) | VPC, least-privilege SG, 3× EC2, EBS-CSI IAM, S3 + DynamoDB backend |
| Cluster | **Ansible** (roles) + **k3s** v1.36 | hardening · k3s-server · k3s-agent; idempotent |
| Ingress / TLS | **ingress-nginx** + **cert-manager** | Let's Encrypt production cert, HTTP-01 |
| Storage | **AWS EBS CSI driver** (gp3) | network-attached PVC survives pod rescheduling |
| App | **TaskApp**: Flask API + React/nginx SPA | images pinned by commit SHA on GHCR |
| Database | **PostgreSQL 16** StatefulSet | Alembic migrations run once via a Job |
| Autoscaling | **HPA** + metrics-server (bundled with k3s) | backend scales 2→6 on CPU/memory |
| GitOps | **Argo CD** | single Application, automated prune + selfHeal |

## Highlights

- **Multi-node HA:** replicas spread across nodes; the app survives a worker being drained.
- **Zero-downtime deploys:** `RollingUpdate` with `maxUnavailable: 0`, readiness gating,
  `preStop` connection draining, and PodDisruptionBudgets.
- **Real persistent storage:** Postgres on an EBS-backed PVC that detaches and re-attaches
  when the pod moves nodes.
- **Autoscaling:** a live HPA driven by real CPU/memory metrics.
- **Defense in depth:** API server (`6443`) firewalled to a single admin IP at both the
  cloud SG and host firewall; default-deny NetworkPolicy with an explicit
  frontend → backend → postgres chain; non-root, capability-dropped containers.
- **Secrets never touch git:** generated out-of-band; `git log -p` is clean.
- **GitOps end-to-end:** commit → Argo auto-sync → live change, no manual `kubectl apply`.

## Repository layout

```
capstone-phoenix/
├── infra/
│   ├── terraform/          # VPC, security group, 3-node fleet, remote state, node IAM
│   └── ansible/            # roles: hardening, k3s-server, k3s-agent
├── manifests/
│   ├── platform/           # ingress-nginx, cert-manager, EBS CSI, gp3 SC, ClusterIssuers
│   └── app/                # TaskApp (kustomize): Postgres, backend, frontend, Job, HPA, NetPol, PDB
├── gitops/                 # Argo CD Application pointing at manifests/app
└── docs/
    ├── ARCHITECTURE.md     # topology, request flow, single-server assumptions fixed
    ├── RUNBOOK.md          # zero → running, day-2 ops, failure recovery
    ├── COST.md             # itemized monthly cost + how to halve it
    ├── EVIDENCE/           # screenshots/logs proving each requirement
    └── ASSIGNMENT.md       # the original brief
```

## Quickstart

Full, reproducible steps are in [`docs/RUNBOOK.md`](docs/RUNBOOK.md). In brief:

```bash
# 1. Infrastructure
cd infra/terraform/bootstrap && terraform init && terraform apply   # remote-state backend
cd .. && terraform init && terraform apply                          # 3-node fleet

# 2. Cluster
cd ../ansible && ansible-playbook site.yml                          # k3s across the nodes
export KUBECONFIG=$(pwd)/kubeconfig && kubectl get nodes            # 3 × Ready

# 3. Platform
cd ../../manifests/platform && ./install-platform.sh               # ingress, TLS, storage

# 4. App (then Argo CD takes over)
cd ../app && ./create-secret.sh && kubectl apply -k .
cd ../../gitops && kubectl apply -f application.yaml                # GitOps owns it from here
```

## Documentation

| Doc | What's in it |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Node/network topology, request flow, design trade-offs, the assumptions table |
| [Runbook](docs/RUNBOOK.md) | Provision from zero, scale, roll back, rotate secrets, recover from failures |
| [Cost](docs/COST.md) | Itemized monthly AWS cost and a concrete plan to halve it |
| [Evidence](docs/EVIDENCE/) | Proof for each requirement (multi-node, TLS, persistence, zero-downtime, HPA, failover, GitOps) |

---

*Built as an individual DevOps capstone. The application (TaskApp) is provided; all
infrastructure, cluster, platform, deployment, GitOps, and documentation are the work here.*
