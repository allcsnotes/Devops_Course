# The current Dockerfile (works, but fails review)
FROM python:3.13.16-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt -r requirements-dev.txt
ENV DB_PASSWORD=demo-password-123
EXPOSE 8000
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
