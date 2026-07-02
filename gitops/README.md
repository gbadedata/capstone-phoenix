# gitops/ — Argo CD owns the application

Argo CD continuously reconciles `manifests/app` from this repo onto the cluster. The graded,
final state is what Argo syncs — not hand-run `kubectl apply`.

## Install Argo CD (once)
```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 7.7.11 \
  -f ../manifests/platform/values/argocd-values.yaml --wait
```

## Register the application
```bash
kubectl apply -f application.yaml
```

## Access the UI
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
# open http://localhost:8080
# user: admin
# password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## Acceptance / demo (the GitOps points)
```bash
argocd app get taskapp        # or via the UI: Synced + Healthy
```
Then: edit `manifests/app/frontend-deployment.yaml` (replicas 2 -> 3), commit, push, and watch
Argo auto-sync the change with NO manual apply — a third frontend Pod appears on its own.

## Notes
- `selfHeal` + `prune` are on: manual drift is reverted, deleted-from-git resources are removed.
- `ignoreDifferences` on `backend /spec/replicas` stops Argo and the HPA fighting.
- The Secret is created out-of-band (`manifests/app/create-secret.sh`), is not in git, and is
  not managed by Argo — so Argo never tries to prune or overwrite it.
