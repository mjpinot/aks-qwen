Security practices applied:

  ┌────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────┐
  │ Area               │ Decision                                                                                   │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Backend auth       │ OIDC (use_oidc = true) — no stored keys                                                    │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ AKS identity       │ SystemAssigned, local accounts disabled, AAD RBAC                                          │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Network policy     │ Calico — deny-by-default pod traffic                                                       │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Ingress source IPs │ Restricted to Cloudflare IP ranges (https://www.cloudflare.com/ips/) only                  │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Cloudflare         │ proxied = true — hides origin IP                                                           │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Key Vault          │ Purge protection, soft-delete 90 days, deny-by-default network ACL                         │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ GPU node pool      │ Tainted with nvidia.com/gpu=present:NoSchedule — only explicitly scheduled pods land there │
  ├────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ HF token           │ Kubernetes Secret via secretKeyRef, not hardcoded                                          │
  └────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────┘

  To deploy:

  1. Fill terraform.tfvars with your real values (subscription ID, Cloudflare zone, etc.)
  2. Create the backend storage account first (one-time):

     az storage account create --name stqwentfstate --resource-group rg-tfstate --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false
     az storage container create --name tfstate --account-name stqwentfstate

  3. Apply the Kubernetes HuggingFace token secret (requires a free HF account for this model):

     kubectl create secret generic hf-token -n qwen --from-literal=token=<YOUR_HF_TOKEN>

  4. terraform init && terraform apply
  5. Apply the Kubernetes manifest: kubectl apply -f k8s/qwen-deployment.yaml
