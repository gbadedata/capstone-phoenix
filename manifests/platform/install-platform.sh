#!/usr/bin/env bash
set -euo pipefail

# Installs the platform layer onto the k3s cluster:
#   - ingress-nginx      (ingress controller; exposed on all nodes via k3s servicelb)
#   - cert-manager       (Let's Encrypt certificates, HTTP-01)
#   - aws-ebs-csi-driver (real persistent storage for Postgres)
#   - gp3 StorageClass + Let's Encrypt ClusterIssuers
#
# metrics-server is NOT installed here — k3s bundles it (verify: kubectl top nodes).
#
# Prereqs: export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig
# Re-runnable: uses `helm upgrade --install`, so running twice is safe.

# --- Pinned chart versions. Verify/bump with: helm search repo <chart> --versions | head ---
INGRESS_NGINX_VERSION="4.11.3"
CERT_MANAGER_VERSION="v1.16.2"
EBS_CSI_VERSION="2.35.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> [1/6] Adding + updating Helm repos"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver >/dev/null 2>&1 || true
helm repo update

echo ">> [2/6] Installing ingress-nginx (${INGRESS_NGINX_VERSION})"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version "${INGRESS_NGINX_VERSION}" \
  -f "${SCRIPT_DIR}/values/ingress-nginx-values.yaml" \
  --wait --timeout 5m

echo ">> [3/6] Installing cert-manager (${CERT_MANAGER_VERSION})"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true \
  -f "${SCRIPT_DIR}/values/cert-manager-values.yaml" \
  --wait --timeout 5m

echo ">> [4/6] Installing aws-ebs-csi-driver (${EBS_CSI_VERSION})"
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --version "${EBS_CSI_VERSION}" \
  -f "${SCRIPT_DIR}/values/aws-ebs-csi-values.yaml" \
  --wait --timeout 5m

echo ">> [5/6] Applying gp3 StorageClass"
kubectl apply -f "${SCRIPT_DIR}/storageclass-gp3.yaml"

echo ">> [6/6] Applying Let's Encrypt ClusterIssuers"
if grep -q "changeme@example.com" "${SCRIPT_DIR}/clusterissuers.yaml"; then
  echo "!! ERROR: edit clusterissuers.yaml and set your real email first."
  echo "   sed -i 's/changeme@example.com/you@yourmail.com/' ${SCRIPT_DIR}/clusterissuers.yaml"
  exit 1
fi
kubectl apply -f "${SCRIPT_DIR}/clusterissuers.yaml"

cat <<'CHECKS'

>> Platform installed. Verify:
   kubectl get pods -n ingress-nginx
   kubectl get svc  -n ingress-nginx ingress-nginx-controller -o wide
   kubectl get pods -n cert-manager
   kubectl get pods -n kube-system | grep ebs-csi
   kubectl get storageclass
   kubectl get clusterissuer            # both should be READY=True after ~30s
   kubectl top nodes                    # confirms k3s metrics-server works
CHECKS
