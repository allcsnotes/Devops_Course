# simulated allcsvideos users (M16-L01): open-loop load, one CSV line per request
FROM python:3.13.16-alpine3.23
LABEL course=devops

WORKDIR /t
COPY traffic.py .
USER 10001
CMD ["sleep", "infinity"]
