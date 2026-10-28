# Course Copilot prototype, spring 2023
FROM python:3.9.16-slim-bullseye
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
