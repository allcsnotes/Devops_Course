# allcsvideos catalog API, lab build for the M17 game day
FROM python:3.13.16-slim
LABEL course=devops
ENV PYTHONUNBUFFERED=1 TZ=IST-5:30
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api.py ./
USER 10001
EXPOSE 8080 9100
CMD ["python", "api.py"]
