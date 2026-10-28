# Course Copilot, M16-B01 lab build. Python 3.13, OpenTelemetry 1.45.1 / 0.66b1.
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,id=m16-full-pip,target=/root/.cache/pip pip install -r requirements.txt
COPY app/ app/
USER 10001:10001
EXPOSE 8000
# auto-instrumentation: the opentelemetry-instrument wrapper patches FastAPI and psycopg at startup
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
