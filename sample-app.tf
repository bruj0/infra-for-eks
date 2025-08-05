# Example Terraform file for deploying a sample application with ALB Ingress
# This file shows how to deploy an application that uses the AWS Load Balancer Controller

# Sample application deployment
resource "kubernetes_deployment" "sample_app" {
  metadata {
    name      = "sample-app"
    namespace = "default"
    labels = {
      app = "sample-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sample-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "sample-app"
        }
      }

      spec {
        container {
          image = "nginx:1.25-alpine"
          name  = "nginx"

          port {
            container_port = 80
          }

          # Simple custom index page
          volume_mount {
            name       = "custom-html"
            mount_path = "/usr/share/nginx/html"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }

        volume {
          name = "custom-html"
          config_map {
            name = kubernetes_config_map.sample_app_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [module.eks]
}

# ConfigMap with custom HTML
resource "kubernetes_config_map" "sample_app_config" {
  metadata {
    name      = "sample-app-config"
    namespace = "default"
  }

  data = {
    "index.html" = <<-EOF
      <!DOCTYPE html>
      <html>
      <head>
          <title>Sample EKS App</title>
          <style>
              body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
              .container { max-width: 600px; margin: 0 auto; }
              .success { color: #28a745; }
          </style>
      </head>
      <body>
          <div class="container">
              <h1 class="success">🎉 EKS Cluster is Running!</h1>
              <p>This is a sample application running on your minimal EKS cluster.</p>
              <p>AWS Load Balancer Controller is working correctly.</p>
              <hr>
              <p><strong>Cluster:</strong> ${var.cluster_name}</p>
              <p><strong>Region:</strong> ${var.aws_region}</p>
              <p><strong>Cost Optimization:</strong> Spot instances, Single AZ, Minimal resources</p>
          </div>
      </body>
      </html>
    EOF
  }

  depends_on = [module.eks]
}

# Service for the sample application
resource "kubernetes_service" "sample_app" {
  metadata {
    name      = "sample-app-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "sample-app"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [module.eks]
}

# Ingress with ALB annotations
resource "kubernetes_ingress_v1" "sample_app" {
  metadata {
    name      = "sample-app-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"                    = "alb"
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "30"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "2"
      "alb.ingress.kubernetes.io/security-groups"      = aws_security_group.alb.id
      # Cost optimization: share ALB across ingresses
      "alb.ingress.kubernetes.io/group.name" = "shared-alb"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.sample_app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller,
    aws_security_group.alb
  ]
}
