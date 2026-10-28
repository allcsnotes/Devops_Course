FROM python:3.13.16-slim
WORKDIR /srv
COPY app/ app/
USER 10001
EXPOSE 8080
CMD ["python", "-m", "app.main"]
