FROM meltano/meltano:v3.7.0-python3.11

WORKDIR /project

# O projeto Meltano entra na imagem e os plugins sao instalados no build.
# Em tempo de execucao o container nao precisa de rede para baixar taps/targets.
COPY meltano/meltano.yml /project/meltano.yml

RUN meltano install

# Diretorio onde o PVC da landing zone e montado.
ENV BANVIC_LANDING_PATH=/opt/banvic/landing \
    MELTANO_ENVIRONMENT=prod

ENTRYPOINT ["meltano"]
CMD ["run", "tap-csv", "target-postgres"]
