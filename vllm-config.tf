# NVIDIA GPU device plugin — required for AKS to expose nvidia.com/gpu resources
resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version          = "0.14.5"
  namespace        = "gpu-operator"
  create_namespace = true

  set {
    name  = "tolerations[0].key"
    value = "nvidia.com/gpu"
  }
  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  # Only run on GPU nodes
  set {
    name  = "nodeSelector.workload"
    value = "llm"
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.gpu]
}

# Namespace-level ResourceQuota — cap GPU consumption
resource "kubernetes_resource_quota" "qwen_gpu" {
  metadata {
    name      = "qwen-gpu-quota"
    namespace = "qwen"
  }
  spec {
    hard = {
      "requests.nvidia.com/gpu" = "5"   # max 5 pods × 1 GPU each
      "limits.nvidia.com/gpu"   = "5"
    }
  }
}

# LimitRange — prevents pods without resource requests from landing on GPU nodes
resource "kubernetes_limit_range" "qwen" {
  metadata {
    name      = "qwen-limits"
    namespace = "qwen"
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "4"
        memory = "24Gi"
      }
      default_request = {
        cpu    = "2"
        memory = "16Gi"
      }
    }
  }
}
