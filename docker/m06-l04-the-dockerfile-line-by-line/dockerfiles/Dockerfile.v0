FROM python:3.12.15-slim
WORKDIR /app
ADD . .
RUN apt-get update
RUN apt-get install -y curl
RUN pip install -r requirements.txt
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
