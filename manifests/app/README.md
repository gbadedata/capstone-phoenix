# manifests/app/ — TaskApp on Kubernetes (kustomize)

Managed by Argo CD (see `gitops/`). Deployable by hand for testing with `kubectl apply -k .`.

## What's here
| File | Purpose |
|---|---|
| namespace / configmap | namespace `taskapp`; non-secret env (DB name/user/host/port, PORT, FLASK_ENV) |
| secret.example.yaml + create-secret.sh | Secret is generated with random values out-of-band — never committed |
| postgres-* | StatefulSet + headless Service + gp3 PVC; runs non-root, `PGDATA` in a subdir |
| backend-* | Deployment (HPA-scaled, min 2) + Service **`backend`:5000**; initContainer waits for a seeded DB |
| frontend-* | Deployment (2 replicas) + Service; initContainer waits for `backend` DNS |
| db-init-job.yaml | run-once schema create + seed; Argo **PreSync** hook |
| ingress.yaml | `taskapp.gbadedata.com` → frontend, `api.gbadedata.com` → backend, cert-manager TLS |
| hpa / networkpolicy / pdb | the Advanced items |

## Deploy by hand (before Argo owns it)
```bash
export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig
cd manifests/app
./create-secret.sh          # random creds → cluster (out-of-band)
kubectl apply -k .          # everything else
kubectl get pods -n taskapp -w
```
Ordering resolves itself: the db-init Job seeds first; backend pods block on their initContainer
until the DB is seeded; frontend blocks until `backend` resolves.

## Key design decisions
- **Backend has no `replicas`** — the HPA owns it (min 2). Avoids Argo/HPA fighting over the field.
- **Soft topology spread** (`ScheduleAnyway`): replicas split across nodes normally, but a drained
  pod lands on the surviving node instead of going Pending — required for the failover demo.
- **DB-init race** is solved by a PreSync Job **and** a backend initContainer that waits for a
  seeded DB, so the app's built-in `create_all()`/`seed_users()` never races across replicas.
- **Probes** match the real app: `tcpSocket:5000` (no `/health` route exists), `httpGet /`
  (frontend), `pg_isready` (Postgres).
- **securityContext**: Postgres is fully hardened (non-root 999, dropped caps, seccomp). Backend/
  frontend get `allowPrivilegeEscalation:false` + `seccompProfile` now; full non-root is a
  one-line follow-up after confirming each image's user (`kubectl exec ... -- id`).

## TLS rollout
Ingress starts on `letsencrypt-staging`. Once a staging cert issues, switch the annotation to
`letsencrypt-prod` and re-apply to get the browser-trusted cert.
