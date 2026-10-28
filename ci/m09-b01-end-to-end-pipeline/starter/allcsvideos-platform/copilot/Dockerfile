# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=3.12.15

# 1) build: a virtual environment with the app's dependencies
FROM python:${PYTHON_VERSION}-slim AS build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /build
COPY requirements.txt .
RUN --mount=type=cache,id=allcsvideos-pip,target=/root/.cache/pip \
    pip install -r requirements.txt

# 2) test: build + test tools + the tests (only with --target test)
FROM build AS test
COPY requirements-dev.txt .
RUN --mount=type=cache,id=allcsvideos-pip,target=/root/.cache/pip \
    pip install -r requirements-dev.txt
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY tests/ tests/
RUN python -m pytest -q -m "not integration"

# 3) runtime: slim Python + the venv + the app (and its migrations), nothing else
FROM python:${PYTHON_VERSION}-slim AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/venv/bin:$PATH \
    COURSE_INDEX=/app/data/courses.json
RUN groupadd --gid 10001 copilot \
 && useradd --uid 10001 --gid copilot --no-create-home copilot
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
COPY db/ db/
COPY docker-entrypoint.sh .
ARG APP_VERSION=dev
ARG APP_REVISION=unknown
ENV APP_VERSION=${APP_VERSION} APP_REVISION=${APP_REVISION}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=2s --timeout=2s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
