# allcsvideos API (lab build): settings come from the cluster (ConfigMaps, Secrets), never from the image.
FROM python:3.13.16-alpine3.23
LABEL course=devops
ARG VERSION=1.4.0
ENV APP_VERSION=${VERSION} PYTHONUNBUFFERED=1
WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
