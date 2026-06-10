# AKS Qwen — vLLM Inference on Azure

Production-ready Terraform + Kubernetes stack to run **Qwen3.5-Coder-2B-Instruct** via **vLLM** on **Azure Kubernetes Service**, with GPU autoscaling, Prometheus observability, and Cloudflare as the secure edge.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Internet                               │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌───────────────────────────────────────────────────────────────┐
│                     Cloudflare (proxied)                      │
│         DDoS protection · TLS termination · IP whitelisting   │
└───────────────────────────┬───────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────┐
│                   AKS — nginx Ingress                         │
│              (LoadBalancer — Cloudflare IPs only)             │
└───────────────────────────┬───────────────────────────────────┘
                            │
                    ┌───────┴───────┐
                    ▼               ▼
          ┌──────────────┐  ┌──────────────┐
          │  vLLM Pod 1  │  │  vLLM Pod 2  │  ← min 2, max 5
          │  (GPU node)  │  │  (GPU node)  │
          └──────┬───────┘  └──────┬───────┘
                 │                 │
                 └────────┬────────┘
                          │ /metrics
                          ▼
              ┌─────────────────────┐
              │     Prometheus      │
              │  (kube-prom-stack)  │
              └──────────┬──────────┘
                         │ queries
                         ▼
              ┌─────────────────────┐
              │        KEDA         │
              │  ScaledObject HPA   │
              └──────────┬──────────┘
                         │ scale trigger
                         ▼
              ┌─────────────────────┐
              │   Cluster Autoscaler│
              │   GPU Node Pool     │
              │   min 1 → max 3     │
              └─────────────────────┘
```

---

## Scaling Flow

```
vLLM /metrics ──► Prometheus ──► KEDA ScaledObject
                                      │
              ┌───────────────────────┼──────────────────────────┐
              │                       │                          │
  vllm:num_requests_running   vllm:num_requests_waiting   cooldown 120s
  threshold: 4 req/pod        threshold: 2 req total
              │                       │
              └───────────────────────┘
                          │
                          ▼
             Deployment replicas: 2 ──► 5
             Node pool:           1 ──► 3
```

---

## Repository Structure

```
aks-qwen/
├── backend.tf          # Azure Blob Storage remote state (OIDC)
├── providers.tf        # azurerm · cloudflare · kubernetes · helm
├── variables.tf        # All input variables
├── terraform.tfvars    # Environment values  ← fill this in
├── main.tf             # VNet · AKS · Key Vault · GPU node pool
├── monitoring.tf       # kube-prometheus-stack + ServiceMonitor
├── keda.tf             # KEDA operator
├── ingress.tf          # nginx-ingress Helm + Kubernetes Ingress
├── vllm-config.tf      # NVIDIA device plugin · ResourceQuota · LimitRange
├── outputs.tf          # kubeconfig command · endpoint
└── k8s/
    ├── qwen-deployment.yaml    # Namespace · Deployment · Service
    └── keda-scaledobject.yaml  # TriggerAuthentication · ScaledObject
```

---

## Prerequisites

- Azure subscription with GPU quota (`Standard_NC` family)
- Terraform ≥ 1.6
- `az` CLI authenticated with OIDC / Workload Identity
- Cloudflare account with a managed zone
- Hugging Face account (Qwen2.5-Coder-3B is public — token needed for rate limits)

Fill in `terraform.tfvars` before running:

```hcl
subscription_id      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
tenant_id            = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
cloudflare_zone_id   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
cloudflare_api_token = "your-cloudflare-api-token"
hostname             = "qwen.yourdomain.com"
grafana_admin_password = "strong-password"
```

> ⚠️ Never commit `terraform.tfvars`, `*.tfstate`, or any token to git. All are listed in `.gitignore`.

---

## Deployment

### 1 — Create the Terraform backend (one-time)

```bash
az group create --name rg-tfstate --location eastus

az storage account create \
  --name stqwentfstate \
  --resource-group rg-tfstate \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name tfstate \
  --account-name stqwentfstate
```

### 2 — Deploy infrastructure

```bash
terraform init
terraform apply
```

Deploys: VNet, AKS cluster, GPU node pool, Key Vault, Prometheus stack, KEDA, nginx ingress, Cloudflare DNS record.

### 3 — Create the Hugging Face token secret

```bash
kubectl create secret generic hf-token \
  -n qwen \
  --from-literal=token=<YOUR_HF_TOKEN>
```

### 4 — Deploy vLLM and autoscaling

```bash
kubectl apply -f k8s/qwen-deployment.yaml
kubectl apply -f k8s/keda-scaledobject.yaml
```

### 5 — Verify

```bash
# Check pods are running
kubectl get pods -n qwen

# Check KEDA is watching the deployment
kubectl get scaledobject -n qwen

# Test the endpoint
curl https://qwen.yourdomain.com/v1/models
```

---

## Autoscaling

| Trigger | Metric | Threshold | Action |
|---------|--------|-----------|--------|
| Primary | `vllm:num_requests_running` | ≥ 4 avg per pod | Scale out |
| Secondary | `vllm:num_requests_waiting` | ≥ 2 queued total | Scale out immediately |

| Parameter | Value |
|-----------|-------|
| Min replicas | 2 |
| Max replicas | 5 |
| Polling interval | 15 s |
| Cooldown | 120 s |
| VPA | Disabled |

---

## GPU & vLLM Optimizations

### Node pool (AKS)

| Setting | Value | Reason |
|---------|-------|--------|
| `os_disk_type` | `Ephemeral` | Lower I/O latency for model weight loading |
| `cpu_manager_policy` | `static` | Dedicate CPUs — no noisy-neighbor stealing |
| `topology_manager_policy` | `best-effort` | Align CPU + GPU on same NUMA node |
| `transparent_huge_page_enabled` | `always` | PyTorch/CUDA THP benefit |
| `kernel_shm_max` | 16 GiB | CUDA IPC requires large kernel-level shm |
| `net_core_rmem/wmem_max` | 128 MiB | High-throughput token streaming |

### Pod (Kubernetes)

| Setting | Value | Reason |
|---------|-------|--------|
| `/dev/shm` volume | 8 GiB (Memory) | Default 64 MiB causes CUDA tensor sharing failures |
| `model-cache` volume | 20 GiB | Avoids re-downloading ~6 GB weights on restart |
| `--gpu-memory-utilization` | `0.90` | Explicit KV cache allocation, prevents OOM |
| `terminationGracePeriodSeconds` | 120 s | Drains in-flight requests on scale-down |
| `preStop sleep` | 30 s | Buffer before SIGTERM reaches vLLM process |
| `topologySpreadConstraints` | 1 per node | One vLLM pod per GPU node — no GPU contention |
| `VLLM_WORKER_MULTIPROC_METHOD` | `spawn` | Required on AKS — `fork` breaks with CUDA |

---

## Security

| Area | Decision |
|------|----------|
| Backend auth | OIDC (`use_oidc = true`) — no stored keys |
| AKS identity | `SystemAssigned`, local accounts disabled, Azure AD RBAC |
| Network policy | Calico — deny-by-default pod traffic |
| Ingress source IPs | Restricted to [Cloudflare IP ranges](https://www.cloudflare.com/ips/) |
| Cloudflare | `proxied = true` — hides origin IP |
| Key Vault | Purge protection, 90-day soft delete, deny-by-default ACL |
| GPU nodes | Tainted `nvidia.com/gpu=present:NoSchedule` — workload isolation |
| GPU quota | `ResourceQuota` caps at 5 GPUs (matches max KEDA replicas) |

---

## Cost Reference

> Prices are estimates for **East US**. Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for exact figures.

### Scenario: Standard_NC4as_T4_v3 (NVIDIA T4 — recommended for Qwen 3B)

| Resource | Est. cost/month |
|----------|----------------|
| AKS control plane | ~$74 |
| System node (Standard_D2s_v3 × 1) | ~$70 |
| GPU node (NC4as_T4_v3 × 1, 24/7) | ~$510 |
| Load Balancer | ~$18 |
| Key Vault + Log Analytics | ~$23 |
| **Total (min replicas, 24/7)** | **~$695/month** |

### Scenario: Scale to max (3 × T4, peak traffic)

| Resource | Est. cost/month |
|----------|----------------|
| Base infrastructure | ~$195 |
| 3 × GPU nodes (NC4as_T4_v3) | ~$1,530 |
| **Total (max replicas)** | **~$1,725/month** |

### Cost optimization: scale-to-zero GPU nodes

Set `min_node_count = 0` in `terraform.tfvars` and `minReplicaCount: 0` in the ScaledObject. GPU nodes are removed when idle.

| Usage pattern | Est. cost/month |
|---------------|----------------|
| 8 h/day active | ~$165 (base) + ~$170 (GPU) = **~$335/month** |

**Potential saving: 40–60% vs always-on.**

---

## Observability

- **Prometheus** — scrapes vLLM `/metrics` every 15 s via `ServiceMonitor`
- **Grafana** — available at the cluster ingress; login with `grafana_admin_password`
- **KEDA** — exposes scaling decisions as Kubernetes events (`kubectl describe scaledobject -n qwen`)

Key vLLM metrics to dashboard:

```
vllm:num_requests_running       # active inference requests
vllm:num_requests_waiting       # queued requests
vllm:gpu_cache_usage_perc       # KV cache utilisation
vllm:time_to_first_token_seconds # TTFT latency
vllm:e2e_request_latency_seconds # end-to-end latency
```
