# Runbook

Operational guide: provision the whole stack from nothing, run day-2 operations, and recover
from failures. Every command here has been run against the live cluster. A teammate should be
able to rebuild an identical HTTPS, multi-node, GitOps-managed TaskApp from this document alone.

**Prerequisites (control machine):** `aws` CLI v2 (configured, region `eu-west-2`), `terraform`
≥ 1.5, `ansible`, `kubectl`, `helm`, and an SSH keypair at `~/.ssh/id_ed25519`.

---

## 1. Provision from zero

```bash
# ── Infrastructure (Terraform) ─────────────────────────────────────────────
cd infra/terraform/bootstrap
terraform init && terraform apply          # creates the S3 state bucket + DynamoDB lock (once)

cd ..
cp terraform.tfvars.example terraform.tfvars
terraform init                             # configures the S3 remote backend
terraform apply                            # 3 EC2 nodes, EIPs, SG, node IAM
# Terraform also writes ../ansible/inventory/hosts.ini from the live IPs.

# ── Cluster (Ansible) ──────────────────────────────────────────────────────
cd ../ansible
ansible-galaxy collection install community.general
ansible all -m ping                        # 3 × SUCCESS
ansible-playbook site.yml                  # hardening + k3s server/agents
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide                  # control-plane + 2 workers = Ready

# ── Platform (Helm) ────────────────────────────────────────────────────────
cd ../../manifests/platform
sed -i 's/changeme@example.com/YOUR_EMAIL/' clusterissuers.yaml   # once
./install-platform.sh                      # ingress-nginx, cert-manager, EBS CSI, gp3 SC, issuers
kubectl get clusterissuer                  # both READY=True

# ── DNS ────────────────────────────────────────────────────────────────────
# At the registrar (GoDaddy), create A records:
#   taskapp  → <control-plane EIP>
#   api      → <control-plane EIP>

# ── Application ────────────────────────────────────────────────────────────
cd ../app
./create-secret.sh                         # random creds → cluster (out-of-band, not in git)
kubectl apply -k .                         # Postgres, backend, frontend, db-init Job, ingress, HPA, NetPol, PDB
kubectl get pods -n taskapp -w             # db-init Completes, then backends/frontends Ready

# ── GitOps takes over (Argo CD) ────────────────────────────────────────────
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version 7.7.11 -f ../platform/values/argocd-values.yaml --wait
cd ../../gitops
kubectl apply -f application.yaml          # Argo now reconciles manifests/app from git
kubectl get application -n argocd          # taskapp: Synced / Healthy
```

Verify the app is live:
```bash
curl -I https://taskapp.gbadedata.com      # HTTP/2 200, valid cert (no -k needed)
# Browser: log in with admin / admin123
```

## 2. Day-2 operations

**Scale a tier.** Prefer a git commit so Argo stays the source of truth:
```bash
# frontend: edit replicas in manifests/app/frontend-deployment.yaml, then
git commit -am "scale frontend to N" && git push        # Argo syncs it
# backend: scaling is automatic (HPA 2–6). To change bounds, edit hpa.yaml and commit.
kubectl get hpa -n taskapp                                # watch current vs target
```

**Roll back a bad deploy.**
```bash
git revert <bad-commit> && git push        # GitOps way: Argo rolls the cluster back
# or, in the Argo UI: History → select last-good revision → Rollback
```

**Run a new migration safely.** Add the Alembic revision to the image, then let the db-init Job
(PreSync hook) run it once ahead of the rollout, so replicas never migrate themselves:
```bash
kubectl delete job db-init -n taskapp && kubectl apply -f manifests/app/db-init-job.yaml
kubectl logs -n taskapp job/db-init         # ">> alembic upgrade head" ... success
```

**Rotate a secret.**
```bash
./manifests/app/create-secret.sh            # regenerates SECRET_KEY (keep DB password if DB exists!)
kubectl rollout restart deploy/backend -n taskapp
# NOTE: to rotate the DB password you must also ALTER it in Postgres, or reinitialise the volume.
```

## 3. Failure recovery

**A worker node dies / is drained** *(the live demo)*. Pods reschedule to healthy nodes; the
app stays up because each tier keeps ≥1 replica (PDB) and DNS points at the control-plane.
```bash
kubectl drain ip-10-0-1-61 --ignore-daemonsets --delete-emptydir-data   # cordon + evict
kubectl get pods -n taskapp -o wide -w      # evicted pods reappear on the other worker
# meanwhile: curl -I https://taskapp.gbadedata.com  keeps returning 200
kubectl uncordon ip-10-0-1-61               # bring it back afterwards
```
Expected recovery: seconds (pods are already `Ready` elsewhere before the drained ones stop,
thanks to `maxUnavailable: 0` + surge).

**A backend pod crashloops.**
```bash
kubectl get pods -n taskapp
kubectl logs -n taskapp <pod> --previous     # logs from the crashed instance
kubectl describe pod -n taskapp <pod>        # Events at the bottom name the cause
# common cause here: DB env not injected → falls back to localhost. Confirm with:
kubectl exec -n taskapp <pod> -c backend -- env | grep -Ei 'database'
```

**A bad migration.** Roll the app back (git revert) and, if the schema was altered, downgrade:
```bash
kubectl run mig-fix -n taskapp --rm -it --restart=Never \
  --image=ghcr.io/ts-a-devops/taskapp-backend:5d6b8fc \
  --env="DATABASE_HOST=postgres" --env="DATABASE_NAME=taskmanager" \
  --env="DATABASE_USER=taskuser" --env="DATABASE_PASSWORD=<pw>" \
  --command -- sh -c 'cd /app && alembic downgrade -1'
```

**Postgres pod is rescheduled: prove the PVC re-attaches.**
```bash
kubectl exec -n taskapp postgres-0 -- psql -U taskuser -d taskmanager -c "SELECT count(*) FROM tasks;"
kubectl delete pod postgres-0 -n taskapp     # StatefulSet recreates it
kubectl get pods -n taskapp -w               # postgres-0 back to Running (EBS volume re-attached)
kubectl exec -n taskapp postgres-0 -- psql -U taskuser -d taskmanager -c "SELECT count(*) FROM tasks;"
# same count → data survived the reschedule
```

## 4. Teardown

```bash
kubectl delete -k manifests/app                          # app
helm uninstall argocd -n argocd
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall cert-manager -n cert-manager
cd infra/terraform && terraform destroy                  # fleet, EIPs, SG, IAM
cd bootstrap && terraform destroy                        # state bucket + lock table (last)
```
