# Course Copilot 1.7.0: the base pinned by digest, every dependency pinned by version and hash
FROM python:3.13.16-slim@sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PATH=/opt/venv/bin:$PATH COURSE_INDEX=/app/data/courses.json
RUN groupadd --gid 10001 copilot && useradd --uid 10001 --gid copilot --no-create-home copilot
COPY requirements.txt /tmp/requirements.txt
# the lock file: --require-hashes refuses any package whose hash is not in it
RUN python -m venv /opt/venv && pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt \
 && /opt/venv/bin/python -m pip uninstall -y -q pip && /usr/local/bin/python -m pip uninstall -y -q pip
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY docker-entrypoint.sh .
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=2s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
