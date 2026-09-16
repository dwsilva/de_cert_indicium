"""Lista o conteudo dos buckets do MinIO.

Executado dentro do pod do scheduler (``make datalake``), reaproveitando a
Connection ``minio_s3`` do Airflow - portanto sem nenhuma credencial em disco.
"""

from __future__ import annotations

from airflow.providers.amazon.aws.hooks.s3 import S3Hook

BUCKETS = ("banvic-datalake", "banvic-airflow-logs")
LIMITE = 15


def main() -> None:
    hook = S3Hook(aws_conn_id="minio_s3")
    for bucket in BUCKETS:
        chaves = hook.list_keys(bucket_name=bucket) or []
        print(f"\n== {bucket}: {len(chaves)} objeto(s)")
        for chave in chaves[:LIMITE]:
            print(f"   {chave}")
        if len(chaves) > LIMITE:
            print(f"   ... e mais {len(chaves) - LIMITE}")


if __name__ == "__main__":
    main()
