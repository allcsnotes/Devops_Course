# syntax=docker/dockerfile:1
# Course Copilot (M09-L03): FastAPI + the OpenFeature SDK + the flagd provider
FROM python:3.12.15-slim AS build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN --mount=type=cache,id=m09l03-pip,target=/root/.cache/pip pip install -r requirements.txt

# tests: both paths of every flag (only with --target test)
FROM build AS test
COPY requirements-dev.txt .
RUN --mount=type=cache,id=m09l03-pip,target=/root/.cache/pip pip install -r requirements-dev.txt
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY tests/ tests/
CMD ["python", "-m", "pytest", "-v", "-p", "no:cacheprovider"]

FROM python:3.12.15-slim AS runtime
ENV PYTHONUNBUFFERED=1 PATH=/opt/venv/bin:$PATH COURSE_INDEX=/app/data/courses.json
RUN useradd --uid 10001 --no-create-home copilot
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
USER 10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
