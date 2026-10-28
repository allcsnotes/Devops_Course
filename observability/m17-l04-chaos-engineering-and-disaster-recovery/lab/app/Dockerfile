# allcsvideos catalog API + the simulated students, lab build for M17-L04
FROM python:3.13.16-slim
LABEL course=devops
# iproute2 gives the tc command: the chaos experiments inject network faults with tc netem
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 && rm -rf /var/lib/apt/lists/*
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api.py loadgen.py ./
USER 10001
EXPOSE 8080
CMD ["python", "api.py"]
