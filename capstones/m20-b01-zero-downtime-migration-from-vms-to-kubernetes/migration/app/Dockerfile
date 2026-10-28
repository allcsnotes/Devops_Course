# allcsvideos catalog API as a container image (M20-B01). The same api.py and requirements.txt the VMs run.
FROM python:3.13.16-slim
LABEL course=devops
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api.py .
USER 10001
EXPOSE 8080
CMD ["python", "api.py"]
