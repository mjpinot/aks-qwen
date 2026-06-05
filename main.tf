data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-qwen-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  sku_name                   = "standard"
  tenant_id                  = var.tenant_id
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# VNet
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address]
}

# Log Analytics for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-qwen-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                             = var.cluster_name
  location                         = azurerm_resource_group.main.location
  resource_group_name              = azurerm_resource_group.main.name
  kubernetes_version               = var.kubernetes_version
  dns_prefix                       = var.cluster_name
  role_based_access_control_enabled = true
  local_account_disabled           = true   # force AAD auth

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D2s_v3"
    node_count          = 1
    vnet_subnet_id      = azurerm_subnet.aks.id
    os_disk_size_gb     = 128
    type                = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true
  }

  # GPU node pool for Qwen inference
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
    duration    = 4
  }
}

# GPU node pool — tuned for vLLM
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.node_count
  min_count             = var.min_node_count
  max_count             = var.max_node_count
  enable_auto_scaling   = true
  vnet_subnet_id        = azurerm_subnet.aks.id
  os_disk_size_gb       = 256
  os_disk_type          = "Ephemeral"   # lower latency I/O vs managed disk

  node_labels = {
    "workload" = "llm"
    "gpu"      = "nvidia"
  }

  node_taints = ["nvidia.com/gpu=present:NoSchedule"]

  # Tune kubelet for large GPU workloads
  kubelet_config {
    cpu_manager_policy        = "static"     # dedicate CPUs to vLLM process
    topology_manager_policy   = "best-effort"
    container_log_max_size_mb = 50
    container_log_max_line    = 1000
  }

  linux_os_config {
    # vLLM / PyTorch benefits from large transparent huge pages
    transparent_huge_page_enabled = "always"
    transparent_huge_page_defrag  = "madvise"

    sysctl_config {
      # Increase shared memory limits for CUDA IPC
      kernel_shm_max = 17179869184   # 16Gi
      kernel_shm_mni = 8192
      # Increase socket buffers for high-throughput inference
      net_core_rmem_max = 134217728
      net_core_wmem_max = 134217728
    }
  }
}

# Cloudflare DNS record pointing to the ingress LB IP
resource "cloudflare_record" "qwen" {
  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  value   = helm_release.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
  type    = "A"
  ttl     = 1
  proxied = true
}

