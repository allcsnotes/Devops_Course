FROM python:3.13.16-slim
RUN pip install --no-cache-dir prometheus-client==0.26.0 && useradd --uid 10001 app
COPY catalog.py /app/catalog.py
USER 10001
CMD ["python", "/app/catalog.py"]
