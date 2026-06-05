# Azure
subscription_id     = "YOUR_SUBSCRIPTION_ID"
tenant_id           = "YOUR_TENANT_ID"
resource_group_name = "rg-qwen-aks"
location            = "eastus"

# AKS
cluster_name        = "aks-qwen-cluster"
kubernetes_version  = "1.29"
node_vm_size        = "Standard_NC6s_v3"   # GPU node for LLM inference
node_count          = 1
min_node_count      = 1
max_node_count      = 3

# Networking
vnet_name           = "vnet-qwen"
vnet_address_space  = "10.0.0.0/16"
subnet_address      = "10.0.1.0/24"

# Cloudflare
cloudflare_zone_id  = "YOUR_CLOUDFLARE_ZONE_ID"
cloudflare_email    = "YOUR_CLOUDFLARE_EMAIL"
hostname            = "qwen.yourdomain.com"

# Backend (Azure Blob Storage)
backend_resource_group  = "rg-tfstate"
backend_storage_account = "stqwentfstate"
backend_container       = "tfstate"

# Monitoring
grafana_admin_password = "CHANGE_ME_STRONG_PASSWORD"

# VPA disabled — KEDA drives pod scaling
vpa_enabled = false
