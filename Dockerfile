# Plain IRIS by default. IRIS for Health adds FHIR output: --build-arg IMAGE=irishealth-community:2026.3.0AI.154.0
ARG IMAGE=iris-community:2026.3.0AI.154.0
FROM $IMAGE

WORKDIR /home/irisowner/dev

COPY merge.cpf /home/irisowner/dev/merge.cpf
ENV PATH="/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < iris.script && \
    iris stop IRIS quietly
