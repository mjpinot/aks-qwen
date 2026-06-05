# nginx ingress controller via Helm
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  # Restrict to Cloudflare IP ranges only
  set {
    name  = "controller.service.loadBalancerSourceRanges"
    value = "{103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17}"
  }
}

# Kubernetes ingress resource for Qwen
resource "kubernetes_ingress_v1" "qwen" {
  metadata {
    name      = "qwen-ingress"
    namespace = "qwen"
    annotations = {
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "50m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "300"
      # Enforce HTTPS (Cloudflare terminates TLS)
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
      # Require Cloudflare-Only header to block direct access
      "nginx.ingress.kubernetes.io/server-snippet" = <<-EOT
        if ($http_x_forwarded_proto != "https") {
          return 301 https://$host$request_uri;
        }
      EOT
    }
  }

  spec {
    rule {
      host = var.hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "qwen-coder"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
