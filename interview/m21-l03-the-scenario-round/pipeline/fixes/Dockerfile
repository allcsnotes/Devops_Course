# catalog-api image. The release number is baked in: docker build --build-arg APP_VERSION=1.5.1
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py pricing.py ./
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 1000
CMD ["opentelemetry-instrument", "python", "app.py"]
