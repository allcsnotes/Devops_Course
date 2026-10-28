# simulated launch-day users (runs as a pod next to the app)
FROM python:3.13.16-alpine3.23
LABEL course=devops
WORKDIR /t
COPY traffic.py .
USER 10001
CMD ["sleep", "infinity"]
