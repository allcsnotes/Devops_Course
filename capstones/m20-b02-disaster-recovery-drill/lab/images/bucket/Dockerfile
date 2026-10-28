# the off-site backup bucket (an S3 stand-in): a tiny object store over HTTP, Python standard library only
FROM python:3.13.16-slim
LABEL course=devops
ENV PYTHONUNBUFFERED=1 TZ=UTC
COPY bucket.py /bucket.py
USER 10001
EXPOSE 9000
CMD ["python", "/bucket.py"]
