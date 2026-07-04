#!/usr/bin/env bash
# Captures the log-based evidence into docs/EVIDENCE/.
# Run from the repo root with KUBECONFIG exported:
#   export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig
#   ./docs/EVIDENCE/capture.sh
set -uo pipefail
NS=taskapp
OUT="docs/EVIDENCE"
DOMAIN="taskapp.gbadedata.com"
API="api.gbadedata.com"
mkdir -p "$OUT"

echo "### 1/6  nodes-ready.log (multi-node, all Ready)"
kubectl get nodes -o wide | tee "$OUT/nodes-ready.log"; echo

echo "### 2/6  pods-spread.log (replicas across different NODEs)"
kubectl get pods -n "$NS" -o wide | tee "$OUT/pods-spread.log"; echo

echo "### 3/6  tls-valid.log (valid public certificate)"
curl -vI "https://$DOMAIN" 2>&1 | tee "$OUT/tls-valid.log"; echo

echo "### 4/6  hpa.log + netpol-enforced.log"
kubectl get hpa -n "$NS" | tee "$OUT/hpa.log"
kubectl get networkpolicy -n "$NS" | tee "$OUT/netpol-enforced.log"; echo

echo "### 5/6  pvc-persist.log (data survives a Postgres pod kill)"
{
  echo "--- create a task so the count is non-zero ---"
  TOKEN=$(curl -s -X POST "https://$API/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"admin123"}' | python3 -c "import sys,json;print(json.load(sys.stdin).get('token',''))")
  curl -s -X POST "https://$API/api/tasks" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d '{"title":"persistence-test","priority":"high","status":"todo"}' >/dev/null && echo "task created"
  echo "--- BEFORE: task count ---"
  kubectl exec -n "$NS" postgres-0 -- psql -U taskuser -d taskmanager -tAc "SELECT count(*) FROM tasks;"
  echo "--- deleting postgres-0 (StatefulSet recreates it; EBS volume re-attaches) ---"
  kubectl delete pod postgres-0 -n "$NS"
  kubectl wait --for=condition=ready pod/postgres-0 -n "$NS" --timeout=180s
  echo "--- AFTER: task count (same value = data survived the reschedule) ---"
  kubectl exec -n "$NS" postgres-0 -- psql -U taskuser -d taskmanager -tAc "SELECT count(*) FROM tasks;"
} | tee "$OUT/pvc-persist.log"; echo

echo "### 6/6  argocd status"
kubectl get application -n argocd | tee "$OUT/argocd-status.log"; echo

echo "DONE. Log evidence is in $OUT/."
echo "Still need SCREENSHOTS (see docs/EVIDENCE/README.md): pods-spread.png, tls-valid.png,"
echo "hpa-scale.png (under load), argocd-synced.png (UI), gitops-autosync.png, failover.png."
