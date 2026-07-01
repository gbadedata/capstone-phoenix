# infra/ansible/ — bare VMs → k3s cluster

Consumes the inventory Terraform generated (`inventory/hosts.ini`) and installs a k3s
cluster: hardened nodes, one control-plane, two joined workers.

## Roles
- **hardening** — enforces no-root-SSH, key-only auth, `ufw`, and `fail2ban`. The AMI's
  `ubuntu` user is the non-root sudo user. ufw is configured to **not** break k3s: it allows
  22/80/443/6443 plus all traffic from the VPC subnet and the pod/service CIDRs, and sets
  `DEFAULT_FORWARD_POLICY=ACCEPT`.
- **k3s-server** — installs k3s on the control-plane with `--disable traefik` (we use
  ingress-nginx), captures the join token, and fetches a kubeconfig to your machine with the
  API address rewritten to the public IP.
- **k3s-agent** — joins each worker using the server's private IP + token.

## Run it
```bash
cd ~/capstone-phoenix/infra/ansible

# one-time: make sure the ufw module is available
ansible-galaxy collection install community.general

# connectivity smoke test
ansible all -m ping

# build the cluster
ansible-playbook site.yml
```

## Acceptance
```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide      # control-plane + 2 workers, all Ready
```

Re-running `ansible-playbook site.yml` a second time must report **changed=0** (idempotent).

## Notes
- `kubeconfig` is written here and is gitignored (never commit it).
- k3s ships a built-in NetworkPolicy controller (kube-router netpol), so the default flannel
  CNI **does** enforce NetworkPolicy — no need to swap to Calico/Cilium for the Advanced
  NetworkPolicy requirement.
- ufw + k3s can drop pod traffic if the FORWARD policy is left at DROP; this role handles it.
