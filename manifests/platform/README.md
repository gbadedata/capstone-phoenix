# manifests/platform/ — cluster platform layer (install once)

Installed once via Helm, documented here and in `docs/RUNBOOK.md`. The **application** is
managed declaratively by Argo CD (see `gitops/`); this platform layer is the bootstrap
underneath it.

| Component | Why | Notes |
|---|---|---|
| ingress-nginx | the front door (HTTP/HTTPS routing) | exposed on all node IPs by k3s servicelb; 2 replicas for HA |
| cert-manager | automatic Let's Encrypt TLS | HTTP-01 validation over port 80 |
| aws-ebs-csi-driver | real network-attached storage | Postgres PVC survives a pod moving nodes; uses the node IAM role |
| gp3 StorageClass | EBS-backed, WaitForFirstConsumer | volume created in the pod's AZ, on demand |
| ClusterIssuers | letsencrypt-staging + letsencrypt-prod | edit the email before applying |

metrics-server is **not** here — k3s ships it (verify with `kubectl top nodes`).

## Install
```bash
export KUBECONFIG=~/capstone-phoenix/infra/ansible/kubeconfig

# set your email for Let's Encrypt (one time)
sed -i 's/changeme@example.com/you@yourmail.com/' clusterissuers.yaml

./install-platform.sh
```

Re-runnable: it uses `helm upgrade --install`.

## Design notes
- **Storage:** k3s default `local-path` binds a volume to one node's disk — a rescheduled
  Postgres pod would lose its data. EBS CSI provides volumes that detach/re-attach across
  nodes (within the AZ), which is why the cluster is single-AZ.
- **Chart versions are pinned** at the top of `install-platform.sh` for reproducibility.
  Record whatever installs into RUNBOOK.md.
