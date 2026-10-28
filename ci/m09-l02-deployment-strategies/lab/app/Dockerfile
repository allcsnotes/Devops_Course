# copilot:<version> - Course Copilot, one image per release (M09-L02)
FROM python:3.12.15-slim
ENV PYTHONUNBUFFERED=1 COURSE_INDEX=/app/data/courses.json
RUN pip install --no-cache-dir fastapi==0.154.0 uvicorn==0.54.0 \
 && groupadd --gid 10001 copilot && useradd --uid 10001 --gid copilot --no-create-home copilot
WORKDIR /app
ARG APP_VERSION
COPY data/ data/
COPY src/${APP_VERSION}/main.py app/main.py
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.version=${APP_VERSION}
USER 10001:10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
