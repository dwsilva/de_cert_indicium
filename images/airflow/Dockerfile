FROM apache/airflow:2.10.5-python3.11

# Dependencias adicionais do projeto (providers de S3/Postgres/Kubernetes).
COPY images/airflow/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# As DAGs viajam dentro da imagem: o deploy passa a ser reprodutivel e a
# demonstracao nao depende de git-sync nem de volume compartilhado.
COPY --chown=airflow:root dags/ /opt/airflow/dags/
COPY --chown=airflow:root sql/ /opt/airflow/sql/

ENV PYTHONPATH=/opt/airflow/dags
