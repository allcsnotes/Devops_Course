# allcsvideos API: returns its pod name and version
FROM python:3.13.16-alpine3.23
ARG APP_VERSION
LABEL course=devops
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1
WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
