# allcsvideos storefront: one image per version (1.0.0, 2.0.0, 3.0.0 = staged bad build)
FROM python:3.13.16-alpine3.23
ARG APP_VERSION
LABEL course=devops
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1
WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
