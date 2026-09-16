locals {
  labels = {
    "app.kubernetes.io/part-of"    = "banvic-data-platform"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  postgres_host = "postgres-dw.${var.namespace}.svc.cluster.local"
  minio_host    = "minio.${var.namespace}.svc.cluster.local"

  # Senha codificada para poder ser usada com seguranca dentro de URIs.
  pg_password_urlencoded = urlencode(var.postgres_password)

  dw_connection_uri = format(
    "postgresql://%s:%s@%s:5432/%s",
    var.postgres_user,
    local.pg_password_urlencoded,
    local.postgres_host,
    var.postgres_dw_database,
  )

  airflow_metadata_uri = format(
    "postgresql://%s:%s@%s:5432/%s",
    var.postgres_user,
    local.pg_password_urlencoded,
    local.postgres_host,
    var.airflow_metadata_database,
  )
}

resource "kubernetes_namespace" "banvic" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# ---------------------------------------------------------------------------
# Segredos
# Tudo que e credencial vive em Secret do Kubernetes. Nenhum arquivo do
# repositorio carrega senha: os valores chegam via terraform.tfvars (ignorado
# pelo git) ou via variaveis de ambiente TF_VAR_*.
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "banvic-postgres"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    POSTGRES_USER     = var.postgres_user
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = var.postgres_dw_database
  }
}

resource "kubernetes_secret" "minio" {
  metadata {
    name      = "banvic-minio"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    MINIO_ROOT_USER     = var.minio_root_user
    MINIO_ROOT_PASSWORD = var.minio_root_password
  }
}

resource "kubernetes_secret" "airflow_metadata" {
  metadata {
    name      = "banvic-airflow-metadata"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    connection = local.airflow_metadata_uri
  }
}

resource "kubernetes_secret" "airflow_webserver_key" {
  metadata {
    name      = "banvic-airflow-webserver-key"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    "webserver-secret-key" = var.airflow_webserver_secret_key
  }
}

resource "kubernetes_secret" "airflow_fernet_key" {
  metadata {
    name      = "banvic-airflow-fernet-key"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    "fernet-key" = var.airflow_fernet_key
  }
}

# Segredo consumido pelas DAGs e pelos pods do Meltano (envFrom).
# Concentra a connection do Airflow e as credenciais de origem/destino.
resource "kubernetes_secret" "pipeline_env" {
  metadata {
    name      = "banvic-pipeline-env"
    namespace = kubernetes_namespace.banvic.metadata[0].name
    labels    = local.labels
  }

  data = {
    # Connections nativas do Airflow (postgres e S3/MinIO)
    AIRFLOW_CONN_BANVIC_DW = local.dw_connection_uri
    AIRFLOW_CONN_MINIO_S3  = local.minio_conn_uri

    # Destino do Meltano (target-postgres)
    BANVIC_DW_HOST     = local.postgres_host
    BANVIC_DW_PORT     = "5432"
    BANVIC_DW_USER     = var.postgres_user
    BANVIC_DW_PASSWORD = var.postgres_password
    BANVIC_DW_DATABASE = var.postgres_dw_database
    BANVIC_DW_SCHEMA   = "raw"

    # Data Lake (MinIO / S3 compativel)
    BANVIC_MINIO_ENDPOINT   = "http://${local.minio_host}:9000"
    BANVIC_MINIO_ACCESS_KEY = var.minio_root_user
    BANVIC_MINIO_SECRET_KEY = var.minio_root_password
    BANVIC_MINIO_BUCKET     = var.minio_bucket

    # Origem (arquivos do sistema legado montados via PVC)
    BANVIC_LANDING_PATH = var.landing_mount_path
  }
}
