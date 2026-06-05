terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stqwentfstate"
    container_name       = "tfstate"
    key                  = "aks-qwen.tfstate"
    use_oidc             = true   # Workload Identity / OIDC — no stored credentials
  }
}
