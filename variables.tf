variable "subscription_id" { type = string }
variable "tenant_id"        { type = string }
variable "resource_group_name" { type = string }
variable "location"         { type = string }

variable "cluster_name"      { type = string }
variable "kubernetes_version" { type = string }
variable "node_vm_size"       { type = string }
variable "node_count"         { type = number }
variable "min_node_count"     { type = number }
variable "max_node_count"     { type = number }

variable "vnet_name"          { type = string }
variable "vnet_address_space" { type = string }
variable "subnet_address"     { type = string }

variable "cloudflare_api_token" { type = string, sensitive = true }
variable "cloudflare_zone_id"  { type = string, sensitive = true }
variable "cloudflare_email"    { type = string }
variable "hostname"            { type = string }

variable "backend_resource_group"  { type = string }
variable "backend_storage_account" { type = string }
variable "backend_container"       { type = string }
