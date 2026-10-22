FROM python:3.13-slim AS dependencies

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /service
RUN python -m venv /opt/venv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM dependencies AS test
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY app/ app/
COPY tests/ tests/
CMD ["python", "-m", "pytest", "-q", "-p", "no:cacheprovider"]

FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /service
RUN groupadd --gid 10001 service \
    && useradd --uid 10001 --gid service --no-create-home service
COPY --from=dependencies /opt/venv /opt/venv
COPY app/ app/
USER 10001:10001
EXPOSE 8080
CMD ["gunicorn", "--bind=0.0.0.0:8080", "--workers=2", "--worker-tmp-dir=/tmp", "--no-control-socket", "--access-logfile=-", "--error-logfile=-", "app:create_app()"]
