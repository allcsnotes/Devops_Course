FROM python:3.13.16-slim
RUN apt-get update && apt-get install -y build-essential
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt -r requirements-dev.txt
EXPOSE 8000
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
