# kube-prometheus-stack — includes Prometheus, Grafana, Alertmanager
resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.7.2"
  namespace        = "monitoring"
  create_namespace = true

  values = [<<-EOT
    grafana:
      enabled: true
      adminPassword: "${var.grafana_admin_password}"
    prometheus:
      prometheusSpec:
        # Discover PodMonitors and ServiceMonitors across all namespaces
        podMonitorSelectorNilUsesHelmValues: false
        serviceMonitorSelectorNilUsesHelmValues: false
        retention: 7d
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
    # Disable VPA for all stack components
    verticalPodAutoscaler:
      enabled: false
    alertmanager:
      alertmanagerSpec:
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
    nodeExporter:
      enabled: true
    kubeStateMetrics:
      enabled: true
  EOT
  ]

  depends_on = [azurerm_kubernetes_cluster.main]
}

# ServiceMonitor so Prometheus scrapes vLLM /metrics
resource "kubernetes_manifest" "qwen_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "qwen-coder"
      namespace = "monitoring"
      labels    = { release = "prometheus" }
    }
    spec = {
      namespaceSelector = { matchNames = ["qwen"] }
      selector          = { matchLabels = { app = "qwen-coder" } }
      endpoints = [{
        port     = "http"
        path     = "/metrics"
        interval = "15s"
      }]
    }
  }

  depends_on = [helm_release.prometheus]
}
