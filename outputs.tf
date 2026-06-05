output "kube_config_command" {
  value     = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
  sensitive = false
}

output "ingress_ip" {
  value = try(helm_release.ingress_nginx.status[0].load_balancer[0].ingress[0].ip, "pending")
}

output "qwen_endpoint" {
  value = "https://${var.hostname}/v1"
}
