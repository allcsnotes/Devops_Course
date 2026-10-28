FROM python:3.13.16-slim
WORKDIR /app
COPY logsetup.py app.py ./
USER 10001
CMD ["python", "-u", "app.py"]
