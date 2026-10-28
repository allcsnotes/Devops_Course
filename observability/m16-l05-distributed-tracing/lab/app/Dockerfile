# One image for the three lab services (SERVICE=bff|api|catalog). Python 3.13, pinned OpenTelemetry 1.45.1 / 0.66b1.
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER 1000
# auto-instrumentation: the opentelemetry-instrument wrapper patches Flask, requests, psycopg and logging at startup
CMD ["opentelemetry-instrument", "python", "app.py"]
