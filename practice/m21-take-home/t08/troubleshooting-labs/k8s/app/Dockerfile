# catalog API for the Kubernetes scenarios: distroless Python, standard library only
FROM gcr.io/distroless/python3-debian13@sha256:e8f62938f332884afc903083bd4e2b9e5f5dcd4084aac0db135ffc7c0025f2ce
LABEL course=devops
COPY app.py /app/app.py
ARG VERSION=1.0
ENV APP_VERSION=${VERSION}
USER 65532
ENTRYPOINT ["python3", "-u", "/app/app.py"]
