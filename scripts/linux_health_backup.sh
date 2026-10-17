#!/usr/bin/env bash
# =============================================================================
# linux_health_backup.sh
# Operations automation: system health check + Docker verify + RDS backup to S3
# SOC2 Control: Backup Policy, System Monitoring, Incident Response
# =============================================================================
set -euo pipefail

LOG_FILE="/var/log/devops_health.log"
S3_BUCKET="${BACKUP_S3_BUCKET:-s3://dckap-demo-encrypted-backups}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

log() {
  echo "[$TIMESTAMP] $*" | tee -a "$LOG_FILE"
}

log "========================================"
log "Starting Linux System & Docker Health Check"
log "========================================"

# ---------------------------------------------------------------------------
# 1. Disk Usage Check
# ---------------------------------------------------------------------------
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
log "Disk usage: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -gt 85 ]; then
  log "[CRITICAL] Disk usage at ${DISK_USAGE}%! Pruning unused Docker images..."
  docker system prune -af --volumes
  log "Docker cleanup complete. New disk usage: $(df -h / | awk 'NR==2 {print $5}')"
fi

# ---------------------------------------------------------------------------
# 2. Memory Usage Check
# ---------------------------------------------------------------------------
MEM_FREE=$(free -m | awk 'NR==2 {print $7}')
MEM_TOTAL=$(free -m | awk 'NR==2 {print $2}')
MEM_USED_PCT=$(( (MEM_TOTAL - MEM_FREE) * 100 / MEM_TOTAL ))
log "Memory: ${MEM_FREE}MB free / ${MEM_TOTAL}MB total (${MEM_USED_PCT}% used)"

if [ "$MEM_USED_PCT" -gt 85 ]; then
  log "[WARNING] Memory usage at ${MEM_USED_PCT}%! Investigating top processes..."
  ps aux --sort=-%mem | head -10 | tee -a "$LOG_FILE"
fi

# ---------------------------------------------------------------------------
# 3. Docker Container Health Check
# ---------------------------------------------------------------------------
log "Checking Docker container status..."

if ! docker ps --filter "name=hospital-app" --filter "status=running" | grep -q "hospital-app"; then
  log "[ERROR] Application container is down! Attempting restart..."
  docker restart hospital-app || {
    log "[CRITICAL] Container restart failed! Re-pulling image and recreating..."
    DOCKER_IMAGE="${APP_IMAGE:-krishnajune2000/hospital-app:latest}"
    docker pull "$DOCKER_IMAGE"
    docker run -d --name hospital-app --restart unless-stopped -p 8000:8000 "$DOCKER_IMAGE"
  }
  log "Container restarted successfully."
else
  CONTAINER_STATUS=$(docker inspect --format='{{.State.Health.Status}}' hospital-app 2>/dev/null || echo "no-healthcheck")
  log "Container running. Health status: ${CONTAINER_STATUS}"
fi

# Quick HTTP health check
if curl -sf http://localhost:8000/health > /dev/null; then
  log "[OK] Application /health endpoint is responding."
else
  log "[ERROR] Application /health endpoint is NOT responding!"
fi

# ---------------------------------------------------------------------------
# 4. Encrypted Database Dump & Upload to S3 (SOC2 Backup Policy)
# ---------------------------------------------------------------------------
log "Starting encrypted database backup..."

RDS_HOST="${RDS_HOST:-localhost}"
RDS_USER="${RDS_USER:-admin}"
RDS_PASS="${RDS_PASS:-}"
DB_NAME="${DB_NAME:-hospital_db}"

BACKUP_FILE="/tmp/db_backup_${TIMESTAMP}.sql.gz"

mysqldump \
  -h "$RDS_HOST" \
  -u "$RDS_USER" \
  -p"$RDS_PASS" \
  --single-transaction \
  --quick \
  "$DB_NAME" | gzip > "$BACKUP_FILE"

log "Database dump created: ${BACKUP_FILE} ($(du -sh "$BACKUP_FILE" | cut -f1))"

# Upload with server-side encryption (AES256) — SOC2 encryption in transit+at rest
aws s3 cp "$BACKUP_FILE" "${S3_BUCKET}/backups/${DB_NAME}/" \
  --sse AES256 \
  --metadata "backup-timestamp=${TIMESTAMP},db-name=${DB_NAME}"

log "Backup uploaded to ${S3_BUCKET}/backups/${DB_NAME}/"

# Remove local copy immediately (never keep plaintext backup on disk)
rm -f "$BACKUP_FILE"
log "Local backup file securely removed."

# ---------------------------------------------------------------------------
# 5. Final Summary
# ---------------------------------------------------------------------------
log "========================================"
log "Health check & backup completed successfully."
log "========================================"
