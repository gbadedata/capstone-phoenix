# Cost

Monthly running cost of the cluster, an honest comparison against the single-server deploy it
replaced, and a concrete plan to halve it.

> Figures are AWS **list prices for `eu-west-2` (London), On-Demand, ~730 hrs/month**, as of the
> build. Verify exact numbers with the [AWS Pricing Calculator](https://calculator.aws/). Taxes
> excluded. Assumes the cluster runs 24×7 (see "How I'd halve this", for a capstone it needn't).

## Monthly itemised cost

| Item | Spec | Qty | $/mo |
|---|---|---:|---:|
| Control-plane VM | `t3.small` (2 vCPU / 2 GiB), on-demand @ ~$0.0236/hr | 1 | 17.23 |
| Worker VMs | `t3.small`, on-demand | 2 | 34.46 |
| Public IPv4 (Elastic IPs) | $0.005/IP/hr, charged on **all** public IPv4 since Feb 2024 | 3 | 10.80 |
| EBS root volumes | `gp3`, 20 GiB @ ~$0.09/GB-mo | 3 | 5.40 |
| EBS PVC (Postgres) | `gp3`, 5 GiB | 1 | 0.45 |
| S3 + DynamoDB (Terraform state) | a few MB + a handful of lock writes | n/a | ~0.50 |
| Route 53 hosted zone | `gbadedata.com` ($0.50/zone + negligible queries) | 1 | 0.50 |
| Data transfer out | light demo traffic (first 100 GB/mo largely free) | n/a | ~1.00 |
| **Total** | | | **≈ $70/mo** |

The three biggest lines are **compute (~$52)**, the **IPv4 charge (~$11)**, which many people
forget is now billed even on attached EIPs, and **EBS (~$6)**.

## Compared to the single-server Compose + Portainer deploy

| | Single server | This cluster |
|---|---:|---:|
| Compute | 1 × `t3.small`, $17.23 | 3 × `t3.small`, $51.69 |
| Public IPv4 | 1 IP, $3.60 | 3 IPs, $10.80 |
| Storage | ~20 GiB gp3, $1.80 | ~65 GiB gp3, $5.85 |
| DNS / state | ~$1.00 | ~$1.00 |
| **≈ Total** | **≈ $24/mo** | **≈ $70/mo** |

**The cluster costs roughly 3× the single server.** What the extra ~$46/mo buys:

- **High availability:** a node (or pod) can die and the app keeps serving; no single host is
  a single point of failure for the workload.
- **Autoscaling:** the backend absorbs load spikes by adding replicas, then scales back down.
- **Zero-downtime deploys:** rollouts and node drains don't drop requests.
- **Self-healing across machines:** failed pods reschedule onto healthy nodes automatically.

**When it is *not* worth it:** low-traffic internal tools, dev/staging, or any app where a few
seconds of downtime during a deploy or reboot is acceptable. For those, one well-backed-up
server at a third of the cost is the right call. The cluster earns its keep only when
availability and scale genuinely matter.

## How I'd halve this (≈ $70 → ≈ $35/mo)

Concrete, stackable changes:

1. **Spot workers.** Run the two agents as Spot instances (fault-tolerant, pods reschedule):
   `t3.small` Spot is typically 60–90% cheaper, taking worker compute from **$34 → ~$7**. Alone
   this is roughly a **$27/mo** saving. (Keep the control-plane On-Demand for stability.)
2. **Shed public IPv4.** Point DNS at a single node and route internally, or adopt an
   IPv6-first/NAT-instance ingress, dropping from 3 Elastic IPs to 1 → saves **~$7/mo**.
3. **Graviton (`t4g.small`, ARM).** ~20% cheaper than `t3.small`, but the app images are
   `amd64`, so this needs a multi-arch image rebuild first (documented as a trade-off, not free).
4. **Two nodes instead of three.** The control plane is schedulable; a 1-server + 1-worker
   cluster still demonstrates real cross-node scheduling and removes one VM + one EIP (~$21/mo),
   at the cost of less failover headroom.

**The single biggest lever for a capstone**, though, is time: nothing here needs to run 24×7.
`terraform destroy` when you're not actively working and re-apply for the next session. The
whole stack is reproducible from the [Runbook](RUNBOOK.md), so a few hours of actual use costs
**a couple of dollars**, not $70. Combining Spot workers + fewer IPv4 + running only during
work sessions takes the effective cost well below half.
