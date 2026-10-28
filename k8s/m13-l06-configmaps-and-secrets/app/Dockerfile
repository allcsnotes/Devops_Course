# allcsvideos API: no settings inside the image. Config comes from ConfigMaps and Secrets at run time.
FROM python:3.13.16-alpine3.23
LABEL course=devops
ENV APP_VERSION=1.5.0 PYTHONUNBUFFERED=1
WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
