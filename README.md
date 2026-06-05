# Security Practices

The following security controls are implemented as part of the platform deployment:

| Area | Security Decision |
|--------|------------------|
| **Backend Authentication** | OIDC (`use_oidc = true`) — no stored credentials or access keys |
| **AKS Identity** | SystemAssigned Managed Identity, local accounts disabled, Azure AD RBAC enabled |
| **Network Policy** | Calico with deny-by-default pod-to-pod traffic |
| **Ingress Source IPs** | Restricted to Cloudflare IP ranges only |
| **Cloudflare Protection** | `proxied = true` to hide origin IP addresses |
| **Azure Key Vault** | Purge protection enabled, soft-delete retention of 90 days, deny-by-default network ACLs |
| **GPU Node Pool** | Tainted with `nvidia.com/gpu=present:NoSchedule` to ensure only GPU workloads are scheduled |
| **Hugging Face Token** | Stored as a Kubernetes Secret using `secretKeyRef`; never hardcoded in source code |

## Additional Security Measures

- No static cloud credentials stored in Terraform.
- Origin infrastructure is protected behind Cloudflare.
- Secrets are managed through Kubernetes and Azure Key Vault.
- Workload isolation enforced through Kubernetes taints and scheduling constraints.
- Network segmentation enforced through Calico Network Policies.
- Azure AD integrated authentication and authorization.

---

# Deployment Guide

## Prerequisites

Before deployment, update the `terraform.tfvars` file with your environment-specific values:

- Azure Subscription ID
- Cloudflare Zone ID
- Domain Name
- Resource Naming Conventions
- Other required variables

---

## 1. Create Terraform Backend Storage (One-Time Setup)

```bash
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

---

## 2. Create the Hugging Face Token Secret

A Hugging Face account is required to access the model.

```bash
kubectl create secret generic hf-token \
  -n qwen \
  --from-literal=token=<YOUR_HF_TOKEN>
```

---

## 3. Deploy Azure Infrastructure

Initialize Terraform and apply the infrastructure:

```bash
terraform init

terraform apply
```

---

## 4. Deploy Kubernetes Workloads

Deploy the application manifests:

```bash
kubectl apply -f k8s/qwen-deployment.yaml
```

---

# Architecture Highlights

- Azure Kubernetes Service (AKS)
- Azure Key Vault
- Azure Managed Identity
- Cloudflare Reverse Proxy
- Calico Network Policies
- GPU-enabled Node Pool
- Hugging Face Model Integration
- Terraform Infrastructure as Code

# Security Notes

⚠️ Never commit:

- `terraform.tfvars`
- Hugging Face tokens
- Service principal credentials
- Terraform state files containing secrets

Recommended `.gitignore` entries:

```gitignore
terraform.tfvars
*.tfstate
*.tfstate.*
.terraform/
.env
```



# Monitoring & Autoscaling

## Components Added

### Monitoring

| File | Description |
|--------|-------------|
| `monitoring.tf` | Deploys `kube-prometheus-stack` using Helm. Vertical Pod Autoscaler (VPA) is explicitly disabled across all components. Includes a `ServiceMonitor` that scrapes the vLLM `/metrics` endpoint. |

### Event-Driven Autoscaling

| File | Description |
|--------|-------------|
| `keda.tf` | Deploys the KEDA Operator using Helm. |
| `k8s/keda-scaledobject.yaml` | Defines a KEDA `ScaledObject` using Prometheus metrics from vLLM. |

---

## Modified Files

| File | Changes |
|--------|---------|
| `k8s/qwen-deployment.yaml` | Increased replicas to `2` and added Prometheus scrape annotations. |
| `variables.tf` | Added `grafana_admin_password` (sensitive) and `vpa_enabled = false`. |
| `terraform.tfvars` | Added values for Grafana administration and VPA configuration. |

---

# Autoscaling Strategy

The deployment uses **KEDA + Prometheus** to scale the vLLM inference service based on native vLLM metrics.

## Scaling Triggers

| Trigger | Metric | Threshold | Purpose |
|----------|----------|------------|---------|
| **Primary** | `vllm:num_requests_running` | Average of **4 requests per pod** | Scale out when pods are actively processing multiple requests. |
| **Secondary** | `vllm:num_requests_waiting` | **2 queued requests** | Scale out immediately when requests begin accumulating in the queue. |

### Scaling Behavior

| Setting | Value |
|----------|-------|
| Minimum Replicas | `2` |
| Maximum Replicas | `5` |
| Cooldown Period | `120 seconds` |

> **Note:** GPU nodes can take several minutes to become available. The 120-second cooldown helps prevent unnecessary scale-in and scale-out events.

---

# Deployment Order

## 1. Deploy Infrastructure

This deploys:

- Azure Kubernetes Service (AKS)
- Prometheus Monitoring Stack
- Grafana
- KEDA Operator

```bash
terraform apply
```

---

## 2. Deploy the vLLM Application

```bash
kubectl apply -f k8s/qwen-deployment.yaml
```

---

## 3. Deploy KEDA Autoscaling

```bash
kubectl apply -f k8s/keda-scaledobject.yaml
```

---

# Verification

Verify that KEDA is monitoring the deployment:

```bash
kubectl get scaledobject -n qwen
```

Expected output:

```text
NAME            READY   ACTIVE   FALLBACK   PAUSED   TRIGGERS   AGE
qwen-scaler     True    False    False      Unknown  2          <age>
```

---

# Observability

The platform exposes metrics through:

- Prometheus
- Grafana Dashboards
- KEDA Metrics Adapter
- Native vLLM Metrics Endpoint (`/metrics`)

Key vLLM metrics used for scaling:

```text
vllm:num_requests_running
vllm:num_requests_waiting
```

These metrics provide real-time visibility into model utilization, request concurrency, and queue depth.



# vLLM Performance & GPU Optimization

This deployment includes several AKS, Kubernetes, and vLLM optimizations specifically designed for high-throughput LLM inference workloads running on NVIDIA GPUs.

---

## GPU Node Pool Optimizations

The GPU node pool is configured with performance-oriented settings to improve model loading times, reduce latency, and maximize GPU utilization.

| Setting | Value | Purpose |
|----------|----------|----------|
| `os_disk_type` | `Ephemeral` | Reduces I/O latency during model weight loading. |
| `cpu_manager_policy` | `static` | Provides dedicated CPU allocation and prevents noisy-neighbor CPU contention. |
| `topology_manager_policy` | `best-effort` | Improves CPU, memory, and GPU NUMA alignment. |
| `transparent_huge_page_enabled` | `always` | Improves PyTorch and CUDA memory management performance. |
| `kernel_shm_max` | `16Gi` | Supports CUDA IPC workloads requiring large shared memory segments. |
| `net.core.rmem_max` | `128Mi` | Increases network receive buffers for high-throughput token streaming. |
| `net.core.wmem_max` | `128Mi` | Increases network transmit buffers for inference traffic. |

---

## Pod-Level Optimizations

The vLLM deployment includes Kubernetes-level tuning to improve reliability, startup behavior, and GPU utilization.

| Setting | Purpose |
|----------|----------|
| `terminationGracePeriodSeconds: 120` | Allows active requests to complete before pod termination. |
| `preStop: sleep 30` | Provides additional drain time during KEDA scale-down events. |
| `topologySpreadConstraints` | Ensures a maximum of one vLLM pod per GPU node. |
| `initContainer: nvidia-smi` | Validates GPU readiness before loading the model. |
| `/dev/shm` memory volume (8Gi) | Prevents CUDA tensor-sharing failures caused by the default 64Mi shared memory allocation. |
| Hugging Face model cache volume | Prevents repeated downloads of large model artifacts during pod restarts. |
| `--gpu-memory-utilization 0.90` | Explicitly reserves GPU memory for KV cache management and reduces OOM events. |
| `VLLM_WORKER_MULTIPROC_METHOD=spawn` | Recommended multiprocessing mode for CUDA workloads on AKS. |
| `TOKENIZERS_PARALLELISM=false` | Reduces unnecessary tokenizer warnings and log noise. |

---

## NVIDIA GPU Support

### `vllm-config.tf`

This module installs and configures GPU-related Kubernetes components.

### NVIDIA Device Plugin

The NVIDIA Device Plugin is installed through Helm and is required for Kubernetes to expose the:

```text
nvidia.com/gpu
```

resource to workloads.

Without this component, GPU scheduling will not function.

---

## Resource Governance

### ResourceQuota

A namespace-level ResourceQuota limits GPU consumption:

| Resource | Limit |
|-----------|--------|
| GPUs | 5 |

This matches the maximum replica count configured in KEDA.

---

### LimitRange

A LimitRange is applied to prevent workloads without resource requests from being scheduled onto expensive GPU nodes.

Benefits include:

- Preventing accidental GPU consumption
- Enforcing resource request best practices
- Improving cluster utilization
- Reducing operational costs

---

## GPU Scheduling Strategy

The deployment combines multiple mechanisms to ensure predictable GPU allocation:

### Node Taints

```text
nvidia.com/gpu=present:NoSchedule
```

Only workloads with the corresponding toleration can run on GPU nodes.

### Topology Spread Constraints

```text
maxSkew: 1
```

Ensures vLLM replicas are evenly distributed across GPU nodes.

### Dedicated CPU Allocation

```text
cpu_manager_policy = static
```

Guarantees CPU resources remain available to GPU workloads and prevents contention from neighboring pods.

---

## Expected Benefits

| Area | Benefit |
|--------|----------|
| Model Startup | Faster model loading and reduced initialization time |
| Throughput | Higher concurrent request handling |
| GPU Utilization | Improved GPU saturation and KV cache efficiency |
| Stability | Fewer OOM and CUDA IPC failures |
| Scaling | Safer KEDA scale-up and scale-down behavior |
| Cost Efficiency | Better utilization of expensive GPU resources |

---

## Deployment Architecture

```text
                    Internet
                        │
                        ▼
                 Cloudflare Proxy
                        │
                        ▼
                    AKS Ingress
                        │
                        ▼
                 vLLM Deployment
                        │
        ┌───────────────┼───────────────┐
        │                               │
        ▼                               ▼
  Hugging Face Cache             /metrics Endpoint
        │                               │
        ▼                               ▼
  Persistent Volume          Prometheus ServiceMonitor
                                        │
                                        ▼
                                    Prometheus
                                        │
                                        ▼
                                      KEDA
                                        │
                                        ▼
                               Horizontal Scaling
                                 (2 → 5 replicas)
```
