# ---------------------------------------------------------------------------
# Apache Airflow (chart oficial)
#
# Decisoes:
#  - KubernetesExecutor: cada task vira um pod, entao nao ha Celery/Redis e o
#    consumo de recursos acompanha a carga real.
#  - Banco de metadados apontando para o PostgreSQL proprio do projeto
#    (postgresql.enabled = false), evitando subchart e mantendo uma unica
#    instancia de banco na POC.
#  - Logs remotos no MinIO: os pods de worker sao destruidos no fim da task,
#    logo o log precisa sair do pod para continuar visivel na interface.
#  - DAGs embarcadas na imagem: build reprodutivel e sem dependencia de rede
#    (git-sync) durante a demonstracao.
# ---------------------------------------------------------------------------

locals {
  landing_volume = [{
    name = "banvic-landing"
    persistentVolumeClaim = {
      claimName = kubernetes_persistent_volume_claim.landing.metadata[0].name
    }
  }]

  landing_volume_mount = [{
    name      = "banvic-landing"
    mountPath = var.landing_mount_path
    readOnly  = true
  }]

  airflow_values = {
    executor                 = "KubernetesExecutor"
    defaultAirflowRepository = var.airflow_image_repository
    defaultAirflowTag        = var.airflow_image_tag

    images = {
      airflow = {
        repository = var.airflow_image_repository
        tag        = var.airflow_image_tag
        pullPolicy = "IfNotPresent"
      }
      useDefaultImageForMigration = false
      migrationsWaitTimeout       = 180
    }

    # Componentes desligados: usamos infraestrutura propria/externa.
    postgresql = { enabled = false }
    redis      = { enabled = false }
    flower     = { enabled = false }

    data = {
      metadataSecretName = kubernetes_secret.airflow_metadata.metadata[0].name
    }

    fernetKeySecretName          = kubernetes_secret.airflow_fernet_key.metadata[0].name
    webserverSecretKeySecretName = kubernetes_secret.airflow_webserver_key.metadata[0].name

    # Sem helm hooks: o Terraform gerencia o ciclo de vida dos jobs.
    createUserJob = {
      useHelmHooks   = false
      applyCustomEnv = false
    }
    migrateDatabaseJob = {
      useHelmHooks   = false
      applyCustomEnv = false
    }

    # Configuracao nao sensivel do pipeline.
    env = [
      { name = "BANVIC_NAMESPACE", value = var.namespace },
      { name = "BANVIC_MELTANO_IMAGE", value = var.meltano_image },
      { name = "BANVIC_LANDING_PVC", value = kubernetes_persistent_volume_claim.landing.metadata[0].name },
      { name = "BANVIC_SOURCE_SYSTEM", value = "erp" },
      { name = "BANVIC_PIPELINE_SECRET", value = kubernetes_secret.pipeline_env.metadata[0].name },
      # Connection do tipo filesystem usada pelos FileSensor. Nao carrega
      # credencial, apenas o diretorio base da landing zone.
      {
        name = "AIRFLOW_CONN_FS_BANVIC"
        value = jsonencode({
          conn_type = "fs"
          extra     = { path = var.landing_mount_path }
        })
      },
    ]

    # Credenciais injetadas a partir do Secret (nunca do codigo).
    extraEnvFrom = yamlencode([
      { secretRef = { name = kubernetes_secret.pipeline_env.metadata[0].name } }
    ])

    config = {
      core = {
        load_examples               = "False"
        dags_are_paused_at_creation = "True"
        # Falhas de infraestrutura (pod evicted, no reiniciado) nao devem
        # derrubar a DAG inteira.
        max_active_tasks_per_dag = "16"
      }
      logging = {
        logging_level          = "INFO"
        remote_logging         = "True"
        remote_base_log_folder = "s3://${local.minio_log_bucket}/airflow-logs"
        remote_log_conn_id     = "minio_s3"
      }
      kubernetes_executor = {
        delete_worker_pods = "True"
        # Pods com falha sao preservados para diagnostico.
        delete_worker_pods_on_failure   = "False"
        worker_pods_creation_batch_size = "8"
      }
      webserver = {
        expose_config            = "True"
        warn_deployment_exposure = "False"
      }
      metrics = {
        statsd_on     = "True"
        statsd_host   = "${local.airflow_release_name}-statsd"
        statsd_port   = "9125"
        statsd_prefix = "airflow"
      }
    }

    # Exportador de metricas (scrape via Prometheus em um cenario real).
    statsd = { enabled = true }

    scheduler = {
      replicas          = 1
      extraVolumes      = local.landing_volume
      extraVolumeMounts = local.landing_volume_mount
      resources = {
        requests = { cpu = "200m", memory = "768Mi" }
        limits   = { memory = "2Gi" }
      }
    }

    workers = {
      extraVolumes      = local.landing_volume
      extraVolumeMounts = local.landing_volume_mount
      resources = {
        requests = { cpu = "150m", memory = "512Mi" }
        limits   = { memory = "2Gi" }
      }
    }

    triggerer = {
      enabled           = true
      replicas          = 1
      extraVolumes      = local.landing_volume
      extraVolumeMounts = local.landing_volume_mount
      resources = {
        requests = { cpu = "100m", memory = "512Mi" }
        limits   = { memory = "1Gi" }
      }
    }

    webserver = {
      replicas = 1
      service = {
        type = "NodePort"
        ports = [{
          name       = "airflow-ui"
          port       = 8080
          targetPort = "airflow-ui"
          nodePort   = 30080
        }]
      }
      defaultUser = {
        enabled   = true
        role      = "Admin"
        username  = var.airflow_admin_user
        password  = var.airflow_admin_password
        email     = "admin@banvic.com.br"
        firstName = "Admin"
        lastName  = "BanVic"
      }
      resources = {
        requests = { cpu = "200m", memory = "768Mi" }
        limits   = { memory = "2Gi" }
      }
    }

    # DAGs vem da imagem; nada de PVC ou git-sync.
    dags = {
      persistence = { enabled = false }
      gitSync     = { enabled = false }
    }

    # Logs vao para o MinIO, entao nao precisamos de volume de logs.
    logs = {
      persistence = { enabled = false }
    }
  }

  airflow_release_name = "airflow"
}

resource "helm_release" "airflow" {
  name       = local.airflow_release_name
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  version    = var.airflow_chart_version
  namespace  = kubernetes_namespace.banvic.metadata[0].name

  values = [yamlencode(local.airflow_values)]

  wait          = true
  wait_for_jobs = true
  timeout       = 900

  depends_on = [
    kubernetes_stateful_set.postgres,
    kubernetes_service.postgres,
    kubernetes_job.minio_buckets,
    kubernetes_persistent_volume_claim.landing,
    kubernetes_secret.pipeline_env,
  ]
}
