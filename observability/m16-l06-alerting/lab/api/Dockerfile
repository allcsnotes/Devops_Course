# allcsvideos API, lab build (from M16-L01): metrics + JSON logs
FROM python:3.13.16-slim
LABEL course=devops
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
