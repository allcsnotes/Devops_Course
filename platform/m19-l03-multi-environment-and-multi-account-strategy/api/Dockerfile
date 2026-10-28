FROM python:3.13.16-alpine3.23
ARG APP_VERSION GIT_REV BUILT_AT
ENV APP_VERSION=$APP_VERSION GIT_REV=$GIT_REV BUILT_AT=$BUILT_AT PYTHONUNBUFFERED=1
LABEL course=devops org.opencontainers.image.version=$APP_VERSION org.opencontainers.image.revision=$GIT_REV
COPY app.py /app/app.py
USER 65534
EXPOSE 8080
CMD ["python", "/app/app.py"]
