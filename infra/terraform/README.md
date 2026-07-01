# infra/terraform/ — AWS infrastructure for the k3s cluster

Provisions the fleet the rest of the capstone runs on: a VPC, one public subnet, a
least-privilege security group, and **3 EC2 nodes** (1 k3s server + 2 k3s agents) with
Elastic IPs. State lives **remotely** in S3 with DynamoDB locking.

## Layout
```
terraform/
├── bootstrap/            # run ONCE: creates the S3 state bucket + DynamoDB lock table
├── modules/
│   ├── network/          # VPC, subnet, IGW, route table
│   ├── security_group/   # 22 + 6443 (your IP), 80 + 443 (world), node-to-node
│   └── compute/          # 3 EC2 instances + Elastic IPs
├── templates/            # renders the Ansible inventory from live IPs
├── backend.tf            # remote-state config (points at the bootstrap bucket)
├── providers.tf / versions.tf
├── variables.tf / outputs.tf / main.tf
└── terraform.tfvars.example
```

## Design decisions
- **Single AZ (eu-west-2a).** Postgres uses an EBS-backed PVC later; EBS volumes are
  AZ-scoped, so keeping every node in one AZ lets a rescheduled Postgres pod re-attach its
  volume on another node. The trade-off (no AZ-failure resilience) is documented in
  `docs/ARCHITECTURE.md`. HA here means surviving a *node* failure, which multi-node in one
  AZ satisfies.
- **Public subnet, no NAT gateway.** A NAT gateway is ~$32/mo and would dominate the bill.
  Nodes get public IPs and are locked down by the security group instead.
- **Elastic IPs on every node.** Node addresses survive stop/start, so DNS records and SSH
  targets stay stable. DNS A records for the app will point at the worker EIPs.
- **6443 is closed to the world** — reachable only from your `/32`. Your laptop's `kubectl`
  still works; the internet's does not.

## Prerequisites (on your machine)
1. AWS CLI configured for an account with rights to create VPC/EC2/S3/DynamoDB:
   `aws configure`  (region `eu-west-2`)
2. An SSH keypair. If you don't have one:
   `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519`
3. Terraform >= 1.5.

## Run it
```bash
# 0) Create the remote-state backend (run once)
cd bootstrap
terraform init
terraform apply
cd ..

# 1) Provision the cluster nodes
cp terraform.tfvars.example terraform.tfvars   # edit if you want different sizes/region
terraform init      # configures the S3 backend created above
terraform apply

# 2) Confirm
terraform output
ssh ubuntu@$(terraform output -raw control_plane_public_ip)
```

`terraform apply` also writes `../ansible/inventory/hosts.ini` from the live IPs, so Phase 2
(Ansible) is ready to go immediately.

## Teardown
```bash
terraform destroy                 # removes the fleet
cd bootstrap && terraform destroy # removes state bucket + lock table (do this last)
```

> If the bucket name `gbadedata-capstone-tfstate` is already taken (S3 names are global),
> change it in **both** `bootstrap/variables.tf` and `backend.tf`.
