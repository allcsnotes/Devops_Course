# allcsvideos API, the lab build from M14-L04, reused in M19-L02 (a CPU-heavy recommendation endpoint)
FROM python:3.13.16-alpine3.23
LABEL course=devops
ENV PYTHONUNBUFFERED=1 TZ=IST-5:30
WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
