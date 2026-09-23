# syntax=docker/dockerfile:1
# Shahi Panel Dockerfile
#
# Slim build for tight deploy targets (VibeNest free tier, Railway, etc.):
#   • No compilers, no git, no build-essential
#   • Only curl + ca-certificates in the runtime image
#   • MTProxy not built — feature removed at user's request
#
# Resulting image: ~250MB (vs upstream SpiderPanel's ~700MB).

FROM python:3.13-slim

LABEL org.opencontainers.image.title="Shahi Panel" \
      org.opencontainers.image.source="https://github.com/shahram008/shahi-panel" \
      org.opencontainers.image.description="Xray control panel for subscriptions, nodes, scanners, Telegram automation (MTProxy not included)"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Minimal runtime deps — no compilers, no git. ~10MB installed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl --version | head -1

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && apt-get clean \
    && rm -rf /var/cache/apt /root/.cache /tmp/*

COPY . .

RUN python -m py_compile main.py

# Ports: panel UI/API on 8080; 443 reserved for future TLS termination.
EXPOSE 8080
EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
