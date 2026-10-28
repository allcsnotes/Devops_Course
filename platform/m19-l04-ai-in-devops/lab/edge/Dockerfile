# allcsvideos edge services (lab build): storefront-bff and course-copilot from one file (SERVICE env)
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY edge.py .
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 1000
CMD ["opentelemetry-instrument", "python", "edge.py"]
