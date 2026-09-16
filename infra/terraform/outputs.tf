output "namespace" {
  description = "Namespace da stack."
  value       = kubernetes_namespace.banvic.metadata[0].name
}

output "airflow_url" {
  description = "Interface do Airflow (porta publicada pelo kind)."
  value       = "http://localhost:18080"
}

output "minio_console_url" {
  description = "Console do MinIO."
  value       = "http://localhost:19001"
}

output "dw_connection_hint" {
  description = "Como conectar no Data Warehouse a partir do host."
  value       = "psql -h localhost -p 15432 -U ${var.postgres_user} -d ${var.postgres_dw_database}"
}

output "landing_host_path" {
  description = "Diretorio da landing zone dentro do no do kind."
  value       = var.landing_host_path
}
