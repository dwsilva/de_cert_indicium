# ---------------------------------------------------------------------------
# Landing zone (origem)
# Representa o compartilhamento de arquivos do sistema legado. O diretorio vive
# no no do cluster e e exposto aos pods como um PV/PVC somente leitura, de modo
# que tanto o Airflow quanto o Meltano enxergam exatamente os mesmos arquivos.
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume" "landing" {
  metadata {
    name   = "banvic-landing-pv"
    labels = merge(local.labels, { "app" = "banvic-landing" })
  }

  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "banvic-landing"

    persistent_volume_source {
      host_path {
        path = var.landing_host_path
        type = "DirectoryOrCreate"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "landing" {
  metadata {
    name      = "banvic-landing"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = merge(local.labels, { "app" = "banvic-landing" })
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "banvic-landing"
    volume_name        = kubernetes_persistent_volume.landing.metadata[0].name

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }

  wait_until_bound = true
}
