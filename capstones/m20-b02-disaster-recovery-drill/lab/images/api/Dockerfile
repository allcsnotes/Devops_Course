# allcsvideos catalog API + the simulated students (M20-B02, from the M17-L04 lab image)
FROM python:3.13.16-slim
LABEL course=devops
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api.py loadgen.py ./
USER 10001
EXPOSE 8080
CMD ["python", "api.py"]
