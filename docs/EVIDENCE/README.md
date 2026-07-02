# Evidence

Proof for each graded requirement. Capture the output/screenshot with the command shown and
save it here under the given filename. `KUBECONFIG` must be exported first:
`export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig`

| File | Proves | Capture command |
|---|---|---|
| `nodes-ready.png` | Multi-node cluster, all Ready | `kubectl get nodes -o wide` |
| `pods-spread.png` | Replicas on different nodes | `kubectl get pods -n taskapp -o wide` (note the NODE column) |
| `tls-valid.png` | Valid public certificate | `curl -vI https://taskapp.gbadedata.com` (or SSL Labs A rating) |
| `pvc-persist.log` | Data survives a pod kill | see the "Postgres pod rescheduled" recipe in `../RUNBOOK.md` (count → delete → count) |
| `zero-downtime.log` | Unbroken 200s during a rollout | `while true; do curl -s -o /dev/null -w "%{http_code}\n" https://taskapp.gbadedata.com; sleep 0.5; done` while running `kubectl rollout restart deploy/frontend -n taskapp` |
| `hpa-scale.png` | Replicas climb under load | `kubectl get hpa -n taskapp -w` during a load test (e.g. `hey`/`ab` against the API) |
| `netpol-enforced.png` | Default-deny + allow chain works | `kubectl get networkpolicy -n taskapp` + app still serving `200` |
| `argocd-synced.png` | Argo CD Synced + Healthy | Argo UI resource tree, or `kubectl get application -n argocd` |
| `gitops-autosync.png` | Commit → auto-sync → new pod | `kubectl get pods -n taskapp -l app=frontend -w` after pushing a replica bump |
| `failover.png` | App up after a node drain | `kubectl drain <worker> ...` alongside a running `curl` loop still returning 200 |

## Suggested capture order
1. `nodes-ready` and `pods-spread` (cluster + scheduling).
2. `tls-valid` (HTTPS).
3. `pvc-persist` (storage).
4. `zero-downtime` (rollout) and `hpa-scale` (autoscaling).
5. `netpol-enforced` (security).
6. `argocd-synced` and `gitops-autosync` (GitOps).
7. `failover`: record this one as the live demo video too.
