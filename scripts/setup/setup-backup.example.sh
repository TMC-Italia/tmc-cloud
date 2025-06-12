#!/bin/bash

# Example Data Backup Script
# scripts/setup/setup-backup.example.sh

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
BACKUP_DIR="/var/backups/myapp" # Local directory to store backups temporarily
REMOTE_STORAGE_PATH="s3://my-backup-bucket/myapp/" # e.g., S3, GCS, Azure Blob path
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATABASE_NAME="mydatabase"
DATABASE_USER="backup_user"
# DATABASE_PASSWORD="LOAD_FROM_ENV_OR_SECRET_MANAGER"
DATABASE_HOST="localhost" # Or your DB host

# Retention policy (number of days to keep backups)
RETENTION_DAYS=7

# --- Helper Functions ---
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] INFO: $1"
}

error_exit() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1" >&2
  exit 1
}

# --- Pre-backup Checks ---
log "Starting pre-backup checks..."

# 1. Ensure backup directory exists and is writable
mkdir -p "$BACKUP_DIR"
if [ ! -w "$BACKUP_DIR" ]; then
  error_exit "Backup directory $BACKUP_DIR is not writable."
fi
log "Backup directory is ready."

# 2. Check for required tools (e.g., pg_dump for PostgreSQL, mysqldump for MySQL, rclone/aws-cli for remote storage)
command -v pg_dump >/dev/null 2>&1 || log "WARN: pg_dump (PostgreSQL) not found. Skipping PostgreSQL backup." # Example
# command -v mysqldump >/dev/null 2>&1 || log "WARN: mysqldump (MySQL) not found. Skipping MySQL backup." # Example
command -v rclone >/dev/null 2>&1 || log "WARN: rclone not found. Remote sync might fail if not using other tools like aws-cli."
command -v aws >/dev/null 2>&1 || log "WARN: aws-cli not found. Remote sync to S3 might fail if not using other tools like rclone."
log "Tool check completed."

# --- Backup Procedures ---

# 1. Backup Database (Example: PostgreSQL)
DB_BACKUP_FILE="$BACKUP_DIR/db_backup_${DATABASE_NAME}_${TIMESTAMP}.sql.gz"
log "Backing up PostgreSQL database: $DATABASE_NAME to $DB_BACKUP_FILE..."
# Ensure PGPASSWORD is set as an environment variable if needed and not using other auth methods
# export PGPASSWORD=$DATABASE_PASSWORD
# pg_dump -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "$DATABASE_NAME" | gzip > "$DB_BACKUP_FILE" || error_exit "Database backup failed."
# unset PGPASSWORD
# For this example, we'll just create a placeholder file
touch "$DB_BACKUP_FILE"
log "Database backup completed (placeholder). $DB_BACKUP_FILE"

# 2. Backup Application Data / Important Files (Example: User uploads directory)
APP_DATA_DIR="/srv/myapp/uploads"
APP_DATA_BACKUP_FILE="$BACKUP_DIR/app_data_uploads_${TIMESTAMP}.tar.gz"
if [ -d "$APP_DATA_DIR" ]; then
  log "Backing up application data from $APP_DATA_DIR to $APP_DATA_BACKUP_FILE..."
  # tar -czf "$APP_DATA_BACKUP_FILE" -C "$(dirname "$APP_DATA_DIR")" "$(basename "$APP_DATA_DIR")" || error_exit "Application data backup failed."
  # For this example, we'll just create a placeholder file
  touch "$APP_DATA_BACKUP_FILE"
  log "Application data backup completed (placeholder). $APP_DATA_BACKUP_FILE"
else
  log "Application data directory $APP_DATA_DIR not found. Skipping."
fi

# 3. Backup Configuration Files
CONFIG_DIR="/etc/myapp/config"
CONFIG_BACKUP_FILE="$BACKUP_DIR/config_files_${TIMESTAMP}.tar.gz"
if [ -d "$CONFIG_DIR" ]; then
  log "Backing up configuration files from $CONFIG_DIR to $CONFIG_BACKUP_FILE..."
  # tar -czf "$CONFIG_BACKUP_FILE" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" || error_exit "Configuration files backup failed."
  touch "$CONFIG_BACKUP_FILE"
  log "Configuration files backup completed (placeholder). $CONFIG_BACKUP_FILE"
else
  log "Configuration directory $CONFIG_DIR not found. Skipping."
fi

# --- Transfer to Remote Storage ---
log "Transferring backups to remote storage: $REMOTE_STORAGE_PATH"
# Example using rclone (ensure rclone is configured with a remote named 'myremote')
# rclone copy "$BACKUP_DIR" "myremote:$REMOTE_STORAGE_PATH_BASE/$TIMESTAMP" --include "*.gz" --include "*.sql" || error_exit "Failed to transfer backups to remote storage with rclone."

# Example using AWS CLI (ensure aws-cli is configured and has permissions)
# aws s3 sync "$BACKUP_DIR" "$REMOTE_STORAGE_PATH$TIMESTAMP/" --exclude "*" --include "*.gz" --include "*.sql" || error_exit "Failed to transfer backups to S3 with AWS CLI."
log "Remote transfer simulated. In a real script, implement actual transfer commands."

# --- Local Cleanup ---
log "Cleaning up old local backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "*.gz" -type f -mtime +"$RETENTION_DAYS" -exec echo "Deleting old local backup: {}" \; -exec rm {} \;
# find "$BACKUP_DIR" -name "*.sql" -type f -mtime +"$RETENTION_DAYS" -exec echo "Deleting old local backup: {}" \; -exec rm {} \;
log "Local cleanup completed."

# --- Remote Cleanup (More complex, often handled by lifecycle policies on the storage) ---
log "Remote cleanup should ideally be handled by lifecycle policies on the storage provider (e.g., S3 Lifecycle Rules)."
# If manual remote cleanup is needed, it would require listing remote files and deleting based on date.
# Example logic (pseudo-code):
#   remote_files = rclone lsjson myremote:$REMOTE_STORAGE_PATH_BASE
#   for file in remote_files:
#     if file.timestamp < (now - RETENTION_DAYS):
#       rclone delete myremote:$REMOTE_STORAGE_PATH_BASE/file.name


log "Backup script finished successfully!"
exit 0
