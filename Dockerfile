# syntax=docker/dockerfile:1
# Shahi Panel Dockerfile
#
# Build options:
#   --build-arg SKIP_MTPROXY=0   → build with MTProxy support (full
#                                  upstream behavior; needs ~420MB extra build
#                                  space, won't fit on VibeNest free tier).
#   --build-arg SKIP_MTPROXY=1   → skip MTProxy compile (default for tight
#                                  deploy targets like VibeNest free tier).
#                                  Panel still runs; TG MTProto feature will be
#                                  unavailable.
#
# Default: SKIP_MTPROXY=1 (slim).

ARG PYTHON_VERSION=3.13-slim
ARG SKIP_MTPROXY=1

# ────────────────────────────────────────────────────────────────────
# Stage 1: build MTProxy (only if SKIP_MTPROXY=0)
# ────────────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION} AS mtproxy-builder

ARG SKIP_MTPROXY
ENV DEBIAN_FRONTEND=noninteractive

RUN if [ "$SKIP_MTPROXY" != "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        build-essential git curl ca-certificates libssl-dev zlib1g-dev pkg-config \
      && git clone --depth 1 https://github.com/TelegramMessenger/MTProxy.git /tmp/MTProxy \
      && make -C /tmp/MTProxy \
      && install -m 0755 /tmp/MTProxy/objs/bin/mtproto-proxy /usr/local/bin/mtproto-proxy \
      && rm -rf /tmp/MTProxy /var/lib/apt/lists/*; \
    fi

# ────────────────────────────────────────────────────────────────────
# Stage 2: runtime — slim, just Python + deps + app
# ────────────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION}

LABEL org.opencontainers.image.title="Shahi Panel" \
      org.opencontainers.image.source="https://github.com/shahram008/shahi-panel" \
      org.opencontainers.image.description="Xray control panel for subscriptions, nodes, scanners, Telegram automation"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Only install curl + ca-certificates (no compilers). ~10MB instead of ~424MB.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && (curl --version || true)

# Optionally copy the compiled MTProxy binary from the builder stage.
# When SKIP_MTPROXY=1, the source file doesn't exist — we touch an empty
# marker file first so the COPY works as a no-op fallback.
ARG SKIP_MTPROXY
RUN if [ "$SKIP_MTPROXY" = "1" ]; then \
      mkdir -p /tmp/mtproxy-out && touch /tmp/mtproxy-out/.dummy; \
    else \
      mkdir -p /tmp/mtproxy-out && cp /usr/local/bin/mtproto-proxy /tmp/mtproxy-out/mtproto-proxy 2>/dev/null || true; \
    fi
COPY --from=mtproxy-builder /tmp/mtproxy-out/. /tmp/mtproxy-out/
RUN if [ -s /tmp/mtproxy-out/mtproto-proxy ]; then \
      mv /tmp/mtproxy-out/mtproto-proxy /usr/local/bin/mtproto-proxy && chmod +x /usr/local/bin/mtproto-proxy; \
    fi
RUN rm -rf /tmp/mtproxy-out

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN python -m py_compile main.py \
    && apt-get clean \
    && rm -rf /var/cache/apt /root/.cache /tmp/*

EXPOSE 8080
EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
