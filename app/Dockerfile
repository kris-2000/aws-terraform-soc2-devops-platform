# ---------------------------------------------------------------------------
# SOC2-Hardened Multi-Stage Docker Build
# Stage 1: Build dependencies in an isolated layer
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: Minimal runtime image
# ---------------------------------------------------------------------------
FROM python:3.12-slim
WORKDIR /app

# SOC2 Best Practice: never run containers as root
RUN groupadd -r devops && useradd -r -g devops appuser

# Copy only the installed packages from the build stage
COPY --from=builder /install /usr/local
COPY app.py .

# Drop all Linux capabilities; run as non-root
USER appuser

EXPOSE 8000

# Container health check — required for ALB target-group health checks
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python", "app.py"]
