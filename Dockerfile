# syntax=docker/dockerfile:1
# Shahi Panel Dockerfile — ZERO apt installs, smallest possible base.
#
# Uses python:3.13-alpine (~80MB compressed) instead of python:3.13-slim
# (~350MB) because the Hetzner deployment server's containerd storage
# is exhausted and can't ingest large base images.
#
# Alpine specifics:
#   - musl libc, no glibc → uses manylinux wheels from PyPI
#   - ca-certificates pre-installed in :alpine Python tags
#   - no apt/yum — uses apk (we don't run it; python:3.13-alpine is ready)
#   - if a wheel lacks alpine support, falls back to ephemeral build deps
#     and immediately removes them so they don't bloat the final image
#
# Build: 2-3 steps total, no compilers in final image.
# Resulting image: ~120MB compressed.

FROM python:3.13-alpine

LABEL org.opencontainers.image.title="Shahi Panel" \
      org.opencontainers.image.source="https://github.com/shahram008/shahi-panel" \
      org.opencontainers.image.description="Xray control panel for subscriptions, nodes, scanners, Telegram automation"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt ./

# Try wheels first; if a package needs source build, use ephemeral build deps
# then delete them in the same layer so the final image stays small.
RUN pip install --no-cache-dir -r requirements.txt || \
    (apk add --no-cache --virtual .shahi-build gcc musl-dev libffi-dev openssl-dev cargo rust && \
     pip install --no-cache-dir -r requirements.txt && \
     apk del .shahi-build)

COPY . .

RUN python -m py_compile main.py

EXPOSE 8080
EXPOSE 443

# Healthcheck via Python urllib stdlib (no shell binaries needed)
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request, sys; \
sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=5).status == 200 else sys.exit(1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
