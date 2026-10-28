# 1) build: dependencies in a virtual environment
FROM python:3.13.16-slim AS build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) runtime: slim Python + the venv + the app
FROM python:3.13.16-slim
ENV PATH=/opt/venv/bin:$PATH PYTHONUNBUFFERED=1
RUN useradd --uid 10001 --no-create-home copilot
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
USER 10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
