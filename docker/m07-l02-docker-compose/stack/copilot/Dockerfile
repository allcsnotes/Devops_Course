# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=3.12.15

# 1) build: a virtual environment with the app's dependencies
FROM python:${PYTHON_VERSION}-slim AS build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN --mount=type=cache,id=compose-lab-pip,target=/root/.cache/pip \
    pip install -r requirements.txt

# 2) test: build + test tools + the tests (only with --target test)
FROM build AS test
COPY requirements-dev.txt .
RUN --mount=type=cache,id=compose-lab-pip,target=/root/.cache/pip \
    pip install -r requirements-dev.txt
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY tests/ tests/
RUN python -m pytest -q

# 3) runtime: slim Python + the venv + the app, nothing else
FROM python:${PYTHON_VERSION}-slim AS runtime
ENV PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH \
    COURSE_INDEX=/app/data/courses.json
RUN groupadd --gid 10001 copilot \
 && useradd --uid 10001 --gid copilot --no-create-home copilot
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
COPY docker-entrypoint.sh .
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health', timeout=2)"]
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
