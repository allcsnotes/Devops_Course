# allcsvideos API, M16-B01 lab build. Python 3.13, OpenTelemetry 1.45.1 / 0.66b1.
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,id=m16-full-pip,target=/root/.cache/pip pip install -r requirements.txt
COPY app.py .
USER 1000
# auto-instrumentation: the opentelemetry-instrument wrapper patches Flask, requests and psycopg at startup
CMD ["opentelemetry-instrument", "python", "app.py"]
