FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && python -m pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
