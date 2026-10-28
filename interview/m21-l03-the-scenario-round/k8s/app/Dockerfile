# catalog API for the pod-restart scenario: Python standard library only
FROM python:3.13.16-slim
LABEL course=devops
COPY app.py /app/app.py
USER 1000
ENTRYPOINT ["python", "-u", "/app/app.py"]
