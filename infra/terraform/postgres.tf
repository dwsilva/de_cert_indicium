# ---------------------------------------------------------------------------
# PostgreSQL
# Uma unica instancia hospeda dois bancos logicos:
#   - banvic_dw : Data Warehouse (schemas raw e meta)
#   - airflow   : metadados do orquestrador
# Em producao seriam instancias separadas; na POC isso reduz consumo de
# recursos sem perder o isolamento logico.
# ---------------------------------------------------------------------------

resource "kubernetes_config_map" "postgres_init" {
  metadata {
    name      = "postgres-dw-init"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    "00-init.sql" = <<-SQL
      -- Banco de metadados do Airflow
      CREATE DATABASE ${var.airflow_metadata_database};

      -- Camadas do Data Warehouse
      \connect ${var.postgres_dw_database}

      -- raw  : espelho fiel do sistema de origem (carregado pelo Meltano)
      -- meta : controle operacional do pipeline (auditoria das execucoes)
      CREATE SCHEMA IF NOT EXISTS raw;
      CREATE SCHEMA IF NOT EXISTS meta;

      COMMENT ON SCHEMA raw IS 'Dados do ERP do BanVic carregados sem transformacao';
      COMMENT ON SCHEMA meta IS 'Metadados operacionais do pipeline de ingestao';
    SQL
  }
}

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "postgres-dw"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = merge(local.labels, { "app" = "postgres-dw" })
  }

  spec {
    service_name = "postgres-dw"
    replicas     = 1

    selector {
      match_labels = { "app" = "postgres-dw" }
    }

    template {
      metadata {
        labels = merge(local.labels, { "app" = "postgres-dw" })
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.postgres.metadata[0].name
            }
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "init"
            mount_path = "/docker-entrypoint-initdb.d"
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 12
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\""]
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 6
          }

          resources {
            requests = {
              cpu    = "150m"
              memory = "384Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "init"
          config_map {
            name = kubernetes_config_map.postgres_init.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "4Gi"
          }
        }
      }
    }
  }

  timeouts {
    create = "10m"
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-dw"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = merge(local.labels, { "app" = "postgres-dw" })
  }

  spec {
    type     = "NodePort"
    selector = { "app" = "postgres-dw" }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      # Exposto no host em localhost:15432 (ver infra/kind/cluster.yaml)
      node_port = 30432
    }
  }
}
