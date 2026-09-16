# ---------------------------------------------------------------------------
# MinIO - camada de object storage (Data Lake) compativel com S3.
# Guarda duas coisas:
#   - banvic-datalake      : copia bruta dos arquivos do ERP, particionada por data
#   - banvic-airflow-logs  : logs das tasks (os pods de worker sao efemeros)
# ---------------------------------------------------------------------------

locals {
  minio_log_bucket = "banvic-airflow-logs"

  minio_conn_uri = format(
    "aws://%s:%s@/?endpoint_url=%s&region_name=us-east-1",
    urlencode(var.minio_root_user),
    urlencode(var.minio_root_password),
    urlencode("http://${local.minio_host}:9000"),
  )
}

resource "kubernetes_persistent_volume_claim" "minio_data" {
  metadata {
    name      = "minio-data"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "8Gi"
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = merge(local.labels, { "app" = "minio" })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { "app" = "minio" }
    }

    template {
      metadata {
        labels = merge(local.labels, { "app" = "minio" })
      }

      spec {
        container {
          name  = "minio"
          image = "quay.io/minio/minio:RELEASE.2024-10-13T13-34-11Z"
          args  = ["server", "/data", "--console-address", ":9001"]

          env_from {
            secret_ref {
              name = kubernetes_secret.minio.metadata[0].name
            }
          }

          port {
            name           = "api"
            container_port = 9000
          }

          port {
            name           = "console"
            container_port = 9001
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = 9000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 12
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minio_data.metadata[0].name
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
  }
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = merge(local.labels, { "app" = "minio" })
  }

  spec {
    type     = "NodePort"
    selector = { "app" = "minio" }

    port {
      name        = "api"
      port        = 9000
      target_port = 9000
      node_port   = 30900
    }

    port {
      name        = "console"
      port        = 9001
      target_port = 9001
      node_port   = 30901
    }
  }
}

# Cria os buckets de forma declarativa (equivalente a um "bootstrap" do storage).
resource "kubernetes_job" "minio_buckets" {
  metadata {
    name      = "minio-create-buckets"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  spec {
    backoff_limit = 10

    template {
      metadata {
        labels = local.labels
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "mc"
          image = "quay.io/minio/mc:RELEASE.2024-10-08T09-37-26Z"

          env_from {
            secret_ref {
              name = kubernetes_secret.minio.metadata[0].name
            }
          }

          command = ["/bin/sh", "-c"]
          args = [<<-SH
            set -e
            until mc alias set banvic http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do
              echo "aguardando MinIO..." && sleep 3
            done
            mc mb --ignore-existing banvic/${var.minio_bucket}
            mc mb --ignore-existing banvic/${local.minio_log_bucket}
            mc ls banvic
          SH
          ]
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_deployment.minio, kubernetes_service.minio]
}
