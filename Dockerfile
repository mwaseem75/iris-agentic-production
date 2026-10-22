ARG IMAGE=irishealth-community:2026.3.0AI.154.0
FROM $IMAGE 

WORKDIR /home/irisowner/dev

ARG NAMESPACE="IRISAPP"

## Embedded Python environment
ENV IRISUSERNAME "_SYSTEM"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE $NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/:/usr/irissys/mgr/python
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"



COPY requirements.txt /home/irisowner/dev/requirements.txt
COPY merge.cpf /home/irisowner/dev/merge.cpf
ENV PYTHONPATH="/usr/irissys/lib/python"
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"
WORKDIR /home/irisowner/dev

RUN  python3 -m venv "/home/irisowner/.venvs/mcp-tools" && \
   "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install -r /home/irisowner/dev/requirements.txt --break-system-packages --target /usr/irissys/mgr/python && \
   "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install typing-extensions --upgrade --break-system-packages --target /usr/irissys/mgr/python

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
	iris session IRIS < iris.script && \
    iris stop IRIS quietly