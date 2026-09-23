# syntax=docker/dockerfile:1
# Shahi Panel Dockerfile — ZERO apt installs.
#
# Rationale: the deploying helper container (Coolify / VibeNest) has very
# limited /var/cache/apt space (1-2GB tmpfs), so any `apt-get install`
# — even just curl — fails with "no space left on device".
#
# python:3.13-slim is Debian trixie-slim and already includes:
#   - ca-certificates
#   - python3 with pip
#   - everything we need
# We use Python's stdlib for the healthcheck (no curl needed).
#
# Resulting image: ~200MB compressed.

FROM python:3.13-slim

LABEL org.opencontainers.image.title="Shahi Panel" \
      org.opencontainers.image.source="https://github.com/shahram008/shahi-panel" \
      org.opencontainers.image.description="Xray control panel for subscriptions, nodes, scanners, Telegram automation"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN python -m py_compile main.py

# Ports
EXPOSE 8080
EXPOSE 443

# Healthcheck via Python urllib (no curl in image — avoids apt install)
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request, sys; \
sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=5).status == 200 else sys.exit(1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
