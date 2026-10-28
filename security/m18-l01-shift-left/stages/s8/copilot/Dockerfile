# Course Copilot (lab image): slim Python, a virtual environment, a non-root user (module 7)
FROM python:3.13.16-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PATH=/opt/venv/bin:$PATH COURSE_INDEX=/app/data/courses.json
RUN groupadd --gid 10001 copilot && useradd --uid 10001 --gid copilot --no-create-home copilot
COPY requirements.txt /tmp/requirements.txt
# pip is a build tool: install the dependencies, then remove pip (and the libraries it bundles) from the runtime image
RUN python -m venv /opt/venv && pip install --no-cache-dir -r /tmp/requirements.txt \
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
