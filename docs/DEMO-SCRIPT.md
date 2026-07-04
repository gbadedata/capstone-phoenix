# Demo and Viva Script

Everything you run and say to capture evidence, record the live demos, and defend the build.
Follow it top to bottom. Commands assume you are in the repo root with the kubeconfig loaded:

```bash
cd ~/capstone-phoenix
export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig
```

Layout of this guide:
- **0. Pre-flight** (before you hit record)
- **1. Evidence capture** (mostly automated)
- **2. Demo A: GitOps auto-sync** (on camera)
- **3. Demo B: Zero-downtime rollout** (on camera, optional but strong)
- **4. Demo C: Live failover** (the headline)
- **5. Viva Q&A** (know these cold)
- **6. Reset to a clean state**
- **7. Submission checklist**

---

## 0. Pre-flight

Run these once and confirm everything is green before recording:

```bash
kubectl get nodes -o wide                       # 3 nodes, all Ready
kubectl get pods -n taskapp -o wide             # backend/frontend Running, spread across nodes
kubectl get application -n argocd               # taskapp: Synced / Healthy
curl -I https://taskapp.gbadedata.com           # HTTP/2 200, no cert warning
kubectl get hpa -n taskapp                      # backend, showing current vs target
```

Have two terminals open (you will need both for the failover demo), both with `KUBECONFIG` set.
Have the browser open on `https://taskapp.gbadedata.com` and the Argo CD UI ready
(`kubectl -n argocd port-forward svc/argocd-server 8080:80`, then `http://localhost:8080`,
user `admin`, password from `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`).

---

## 1. Evidence capture

Most of it is automated. From the repo root:

```bash
./docs/EVIDENCE/capture.sh
```

That writes `nodes-ready.log`, `pods-spread.log`, `tls-valid.log`, `hpa.log`,
`netpol-enforced.log`, `pvc-persist.log`, and `argocd-status.log` into `docs/EVIDENCE/`.

Then capture these **screenshots** (the visual ones graders like), saved into `docs/EVIDENCE/`:

- `pods-spread.png`: the terminal showing `kubectl get pods -n taskapp -o wide`, NODE column visible.
- `tls-valid.png`: the browser padlock on `https://taskapp.gbadedata.com`, or an SSL Labs A rating.
- `argocd-synced.png`: the Argo CD UI resource tree, Synced and Healthy.
- `hpa-scale.png`: see the load test just below.
- `gitops-autosync.png` and `failover.png`: produced by Demos A and C.

### HPA under load (for `hpa-scale.png`)

The login endpoint hashes passwords, so hammering it drives real backend CPU and makes the HPA
scale. In one terminal watch the HPA, in another generate load:

```bash
# terminal 1: watch
kubectl get hpa -n taskapp -w

# terminal 2: load (20 parallel clients hitting the CPU-heavy login endpoint)
seq 1 100000 | xargs -P 20 -I{} curl -s -o /dev/null -X POST \
  https://api.gbadedata.com/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin123"}'
```

Watch `REPLICAS` climb from 2 toward 6 as CPU crosses 60%. Screenshot terminal 1 mid-climb as
`hpa-scale.png`, then stop the load (Ctrl-C in terminal 2) and confirm it scales back down.

---

## 2. Demo A: GitOps auto-sync (on camera)

**What it proves:** the cluster's state is driven by Git, not by hand. This is the 10-point
GitOps requirement.

**Say:** "The cluster's desired state lives in my Git repo. Argo CD watches it and reconciles
any change automatically. I never run kubectl apply against the live app. Watch: I'll change
the frontend replica count in Git, and Argo will roll it out on its own."

```bash
# terminal 1: watch the frontend pods
kubectl get pods -n taskapp -l app=frontend -w
```
**On screen:** point out there are currently two frontend pods.

```bash
# terminal 2: make the change in Git only
sed -i 's/replicas: 2/replicas: 3/' manifests/app/frontend-deployment.yaml
git commit -am "demo: scale frontend 2 to 3 via GitOps"
git push
```
**Say:** "That is only a commit to GitHub. I have not touched the cluster."

Argo polls roughly every three minutes. To make it instant on camera, either click **Refresh**
in the Argo UI, or:
```bash
kubectl -n argocd patch application taskapp --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**On screen:** in terminal 1, a **third** frontend pod appears and goes Running. In the Argo UI,
the app briefly shows Progressing then Synced/Healthy.

**Say:** "Argo saw the commit and created the third pod by itself. That is GitOps: commit,
auto-sync, live change, no manual apply." Screenshot the new pod as `gitops-autosync.png`.

---

## 3. Demo B: Zero-downtime rollout (on camera, optional but strong)

**What it proves:** deploys do not drop traffic (`maxUnavailable: 0` + readiness gating +
connection draining).

```bash
# terminal 1: a continuous probe, logged to file
( while true; do printf '%s %s\n' "$(date +%T)" \
  "$(curl -s -o /dev/null -w '%{http_code}' https://taskapp.gbadedata.com)"; sleep 0.5; done ) \
  | tee docs/EVIDENCE/zero-downtime.log
```
**Say:** "I'm hitting the site twice a second and logging the HTTP status. Now I'll trigger a
full rollout of the frontend while this keeps running."

```bash
# terminal 2: roll the deployment
kubectl rollout restart deploy/frontend -n taskapp
kubectl rollout status  deploy/frontend -n taskapp
```
**On screen:** terminal 1 keeps printing `200` the whole time. When the rollout finishes,
Ctrl-C terminal 1.

**Say:** "Every request stayed 200 through the rollout. New pods become Ready before old ones
are removed, and a pre-stop hook drains in-flight connections, so no request is dropped."
The `zero-downtime.log` is your evidence.

---

## 4. Demo C: Live failover (the headline)

**What it proves:** the app survives losing a worker node. This is the required live demo.

First, find which node runs Postgres and pick a **different** worker to drain (so the single
database pod is untouched and the app stays fully up):

```bash
kubectl get pod postgres-0 -n taskapp -o wide           # note its NODE
kubectl get nodes                                        # pick a worker that is NOT that node
```
Call the worker you will drain `WORKER` (for example `ip-10-0-1-201`).

**Say:** "High availability means a worker can fail and the app keeps serving. I'll drain a
worker on camera. Its pods will reschedule onto the other nodes, and the site will stay up the
whole time."

```bash
# terminal 1: continuous probe (proves the app stays up)
( while true; do printf '%s %s\n' "$(date +%T)" \
  "$(curl -s -o /dev/null -w '%{http_code}' https://taskapp.gbadedata.com)"; sleep 0.5; done ) \
  | tee docs/EVIDENCE/failover.log

# terminal 2: watch pods move
kubectl get pods -n taskapp -o wide -w
```

Then, in a third terminal (or pause terminal 2's watch), drain the worker:
```bash
kubectl drain <WORKER> --ignore-daemonsets --delete-emptydir-data
```

**On screen, point out:**
- Terminal 2: the pods that were on `<WORKER>` go Terminating, and replacements appear on the
  other nodes and become Running.
- Terminal 1: the status stays `200` throughout.
- `kubectl get nodes` now shows `<WORKER>` as `Ready,SchedulingDisabled`.

**Say:** "The node is cordoned and its pods evicted. Kubernetes rescheduled them onto the
healthy nodes, the PodDisruptionBudget kept at least one replica of each tier alive, and the
site never stopped serving. Because replica scheduling is soft, the evicted pods landed on the
surviving nodes instead of getting stuck pending."

Bring the node back:
```bash
kubectl uncordon <WORKER>
kubectl get nodes                                        # all Ready again
```
Ctrl-C terminal 1. Screenshot terminal 2 (pods rescheduled) and the unbroken 200s as
`failover.png`.

> If a grader asks what happens when the **Postgres** node itself dies: the EBS volume detaches
> from the dead node and re-attaches to Postgres's replacement pod on another node in the same
> AZ. Recovery is one to two minutes with a brief database blip. A single Postgres replica is a
> known limitation; the production upgrade is an HA Postgres (Patroni) or managed RDS.

---

## 5. Viva Q&A (know these cold)

Short, confident answers to the questions most likely to come up.

**Why k3s rather than full Kubernetes?**
It is a single lightweight binary with the same Kubernetes API, and it bundles exactly what a
small cluster needs: a service load balancer, metrics-server, and a network-policy controller.
Less to run, nothing lost.

**Why a single Availability Zone?**
AWS EBS volumes are AZ-scoped. Keeping every node in one AZ lets a rescheduled Postgres pod
re-attach its existing volume on another node. The trade-off is no resilience to a full-AZ
outage, which is acceptable because the requirement is surviving a node failure, and multi-node
in one AZ covers that. Multi-AZ would need replicated storage such as Longhorn.

**How is zero-downtime achieved?**
`RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1` brings a new pod to Ready before an
old one is removed; readiness probes gate traffic; a `preStop` hook drains connections before
SIGTERM; and PodDisruptionBudgets keep a replica alive during node drains.

**You had a migration problem. What was it and how did you solve it?**
The published image runs Alembic migrations in its entrypoint on every replica start, so at two
or more replicas they race and collide. I run the migration once in a dedicated Job wired as an
Argo PreSync hook, and each backend pod has an init container that blocks until the database is
migrated and seeded, so the replicas never race.

**Why EBS CSI and not the default local-path storage?**
Local-path pins a volume to one node's disk, so a rescheduled Postgres pod would lose its data.
The EBS CSI driver gives a network-attached volume that detaches and re-attaches across nodes.
The driver authenticates through an IAM instance profile on the nodes, so there are no static
keys anywhere.

**How is the Kubernetes API secured?**
Port 6443 is restricted to my single admin IP, enforced twice: at the AWS security group and at
the host firewall. It is never open to the world. Only 80 and 443 are public.

**Does the default flannel CNI actually enforce your NetworkPolicies?**
Yes. k3s bundles kube-router's network-policy controller, so flannel enforces them. I run a
default-deny plus an explicit chain: ingress to frontend, frontend and ingress to backend,
backend to Postgres. I verified the pods stay Ready and the app still serves with the policies
applied.

**Where are your secrets?**
Non-secret config is in a ConfigMap. The Secret is generated with random values out-of-band by
a script and applied straight to the cluster, so nothing sensitive is ever in Git, and
`git log -p` is clean. Argo does not manage the Secret, so it is never pruned. The next step
would be Sealed Secrets so the encrypted form can live in Git.

**Why doesn't Argo CD fight the HPA over replica count?**
The backend Deployment has no `replicas` field, so the HPA owns it, and the Argo Application
ignores differences on `/spec/replicas`. They never conflict.

**What does the cluster cost, and how would you cut it?**
Around $70 a month running 24x7. To halve it: run the workers as Spot instances, reduce the
number of public IPv4 addresses, and, for a project like this, destroy the stack when idle and
recreate it from the runbook, which drops the real cost to a few dollars.

**What is the weakest part, and what would you improve next?**
A single Postgres replica is the main one; HA Postgres or managed RDS is the upgrade. The
ingress enters through one node's IP, which could become multiple A records or a load balancer.
And I would add a Prometheus and Grafana stack for observability.

---

## 6. Reset to a clean state

After the demos:

```bash
# uncordon anything you drained
kubectl get nodes | grep SchedulingDisabled | awk '{print $1}' | xargs -r -n1 kubectl uncordon

# the frontend is now at 3 replicas from Demo A. Keep it (it is your GitOps evidence in Git
# history), or return it to 2 the same way:
sed -i 's/replicas: 3/replicas: 2/' manifests/app/frontend-deployment.yaml
git commit -am "revert demo scale back to 2" && git push

# confirm everything is back to healthy and synced
kubectl get pods -n taskapp -o wide
kubectl get application -n argocd
```

**Cost note:** if you are done for the session, tear down to stop the meter and rebuild later
from the runbook: `cd infra/terraform && terraform destroy` (then `bootstrap` last).

---

## 7. Submission checklist

- [ ] `docs/EVIDENCE/` has: nodes-ready, pods-spread, tls-valid, pvc-persist, zero-downtime,
      hpa-scale, netpol-enforced, argocd-synced, gitops-autosync, failover.
- [ ] Live site loads over HTTPS with a valid cert: `https://taskapp.gbadedata.com`.
- [ ] `kubectl get application -n argocd` shows Synced and Healthy.
- [ ] `git log --oneline` shows the phased, meaningful history and `git log -p` has no secrets.
- [ ] README, ARCHITECTURE, RUNBOOK, COST are complete and committed.
- [ ] Failover demo recorded (node drain, app stays up, pods reschedule).
- [ ] Submission link filled in: the Google Form in the repo README/brief.
