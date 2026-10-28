# syntax=docker/dockerfile:1
# course-search: build, test and runtime stages. Only the runtime stage ships.
ARG PYTHON_IMAGE=python:3.13.16-slim

# 1) build: a virtual environment with the runtime dependencies only
FROM ${PYTHON_IMAGE} AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /src
COPY requirements.txt .
RUN pip install -r requirements.txt \
 && pip uninstall -y pip

# 2) test: the build venv + test tools + the tests. `docker build --target test .` fails if a test fails.
FROM build AS test
COPY requirements-dev.txt .
RUN python -m ensurepip && python -m pip install -r requirements-dev.txt
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY tests/ tests/
RUN python -m pytest -q

# 3) runtime: slim Python, the venv and the app; no pip, no tests, no secrets, not root
FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/venv/bin:$PATH \
    COURSE_INDEX=/app/data/courses.json
# pip is not needed at run time, and its vendored libraries are what scanners flag
RUN python -m pip uninstall -y pip \
 && groupadd --gid 10001 app \
 && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
