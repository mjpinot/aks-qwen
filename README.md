# AKS-Qwen: High-Performance LLM Inference with vLLM on Azure 🚀

This repository contains the Infrastructure as Code (Terraform) and Kubernetes manifests necessary to deploy the **Qwen** model using **vLLM** on **Azure Kubernetes Service (AKS)**. 

The solution is designed for production environments, incorporating GPU acceleration, event-driven autoscaling (KEDA + Prometheus), a secure reverse proxy with Cloudflare, and Azure security best practices.

## 🏗️ Deployment Architecture

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
  Hugging Face Cache             Endpoint /metrics
        │                               │
        ▼                               ▼
 Persistent Volume           Prometheus ServiceMonitor
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


✨ Key FeaturesAgile Infrastructure: Fully managed with Terraform.Smart Autoscaling: Uses KEDA to scale inference pods based on native vLLM metrics (running and waiting requests).GPU Optimization: Dedicated nodes, topologySpreadConstraints, and pod-level optimizations to maximize performance (CUDA IPC, Huge Pages, etc.).Secure by Default: OIDC authentication, Azure Key Vault, Managed Identities, and strict network policies (Calico).📋 PrerequisitesBefore starting the deployment, make sure to update the terraform.tfvars file with the specific values for your environment:Azure Subscription ID.Cloudflare Zone ID.Domain Name.Resource naming conventions.A valid Hugging Face token with access to the Qwen model.⚠️ Security Warning: Never commit your terraform.tfvars file, Hugging Face tokens, credentials, or .tfstate files to the repository. Make sure they are included in your .gitignore.🚀 Deployment Guide1. Create the Terraform Backend (One-time Setup)Create an Azure storage account to securely store the Terraform state:Bashaz storage account create \
  --name stqwentfstate \
  --resource-group rg-tfstate \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name tfstate \
  --account-name stqwentfstate
2. Deploy Infrastructure (Azure and AKS)This step deploys AKS, the monitoring stack (Prometheus/Grafana), and the KEDA operator.Bashterraform init
terraform apply
3. Configure the Hugging Face TokenCreate a Kubernetes secret so vLLM can download the model weights:Bashkubectl create secret generic hf-token \
  -n qwen \
  --from-literal=token=<YOUR_HF_TOKEN>
4. Deploy the Application and AutoscalingApply the Kubernetes manifests to start vLLM and configure KEDA:Bash# Deploy the vLLM application
kubectl apply -f k8s/qwen-deployment.yaml

# Enable autoscaling with KEDA
kubectl apply -f k8s/keda-scaledobject.yaml
Verification: You can verify that KEDA is monitoring the deployment correctly by running:Bashkubectl get scaledobject -n qwen
📈 Autoscaling and ObservabilityAutoscaling is managed by KEDA + Prometheus, reacting in real-time to the workload.TriggerMetricThresholdPurposePrimaryvllm:num_requests_running4 requests/podScales when pods are processing multiple requests concurrently.Secondaryvllm:num_requests_waiting2 requests in queueScales immediately when requests start queuing up.Limits: Minimum 2 replicas, Maximum 5 replicas.Cooldown: 120 seconds (prevents rapid fluctuations while GPU nodes boot up).All observability is exposed through the vLLM /metrics endpoint, collected by the Prometheus ServiceMonitor, and can be visualized in Grafana.



