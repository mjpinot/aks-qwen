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
