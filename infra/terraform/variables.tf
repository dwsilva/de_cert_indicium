variable "kubeconfig_path" {
  description = "Caminho do kubeconfig usado para falar com o cluster kind."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto do kubeconfig."
  type        = string
  default     = "kind-banvic"
}

variable "namespace" {
  description = "Namespace onde toda a stack do BanVic e criada."
  type        = string
  default     = "banvic"
}

# ---------------------------------------------------------------------------
# Credenciais
# Nenhum valor default e definido para senhas: elas vem de terraform.tfvars
# (arquivo fora do versionamento) ou de variaveis de ambiente TF_VAR_*.
# ---------------------------------------------------------------------------
variable "postgres_user" {
  description = "Usuario administrador do PostgreSQL (DW + metadados do Airflow)."
  type        = string
  default     = "banvic"
}

variable "postgres_password" {
  description = "Senha do usuario do PostgreSQL."
  type        = string
  sensitive   = true
}

variable "postgres_dw_database" {
  description = "Banco de dados do Data Warehouse."
  type        = string
  default     = "banvic_dw"
}

variable "airflow_metadata_database" {
  description = "Banco de dados de metadados do Airflow."
  type        = string
  default     = "airflow"
}

variable "minio_root_user" {
  description = "Access key do MinIO."
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "Secret key do MinIO."
  type        = string
  sensitive   = true
}

variable "minio_bucket" {
  description = "Bucket que representa a camada raw do Data Lake."
  type        = string
  default     = "banvic-datalake"
}

variable "airflow_admin_user" {
  description = "Usuario admin da interface do Airflow."
  type        = string
  default     = "admin"
}

variable "airflow_admin_password" {
  description = "Senha do admin da interface do Airflow."
  type        = string
  sensitive   = true
}

variable "airflow_webserver_secret_key" {
  description = "Secret key do webserver do Airflow (assinatura de sessao)."
  type        = string
  sensitive   = true
}

variable "airflow_fernet_key" {
  description = "Fernet key usada pelo Airflow para criptografar connections/variables."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Imagens e armazenamento
# ---------------------------------------------------------------------------
variable "airflow_image_repository" {
  description = "Imagem customizada do Airflow (com DAGs e dependencias do projeto)."
  type        = string
  default     = "banvic/airflow"
}

variable "airflow_image_tag" {
  description = "Tag da imagem do Airflow."
  type        = string
  default     = "local"
}

variable "meltano_image" {
  description = "Imagem do Meltano usada pelo KubernetesPodOperator."
  type        = string
  default     = "banvic/meltano:local"
}

variable "landing_host_path" {
  description = "Diretorio no no do kind que hospeda os arquivos do sistema legado."
  type        = string
  default     = "/mnt/banvic/landing"
}

variable "landing_mount_path" {
  description = "Ponto de montagem da landing zone dentro dos pods."
  type        = string
  default     = "/opt/banvic/landing"
}

variable "airflow_chart_version" {
  description = "Versao do chart oficial apache-airflow/airflow."
  type        = string
  default     = "1.16.0"
}
