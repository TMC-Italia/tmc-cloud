#!/bin/bash

# Example Application Deployment Script
# scripts/deployment/deploy-app.example.sh

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# These variables would typically be set by a CI/CD system or environment variables.
# Replace with your actual values or use environment variables.
APP_NAME="my-application"
DOCKER_IMAGE_NAME="myregistry/my-app"
DOCKER_IMAGE_TAG="latest" # Or a specific version like v1.2.3, or git commit SHA
KUBERNETES_NAMESPACE="my-namespace"
KUBERNETES_DEPLOYMENT_NAME="my-app-deployment"
CONFIG_FILE_PATH="configs/environments/prod.yml" # Path to the production config for the app

# --- Helper Functions ---
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] INFO: $1"
}

error_exit() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1" >&2
  exit 1
}

# --- Pre-deployment Steps ---
log "Starting pre-deployment checks..."

# 1. Check for required tools (e.g., kubectl, docker, git)
command -v kubectl >/dev/null 2>&1 || error_exit "kubectl is not installed. Aborting."
command -v docker >/dev/null 2>&1 || error_exit "docker is not installed. Aborting."
log "Required tools are available."

# 2. Ensure configuration file exists (if applicable)
# if [ ! -f "$CONFIG_FILE_PATH" ]; then
#   error_exit "Production configuration file not found at $CONFIG_FILE_PATH. Aborting."
# fi
# log "Configuration file found."

# 3. (Optional) Put application into maintenance mode
# log "Putting application into maintenance mode..."
# kubectl annotate deployment $KUBERNETES_DEPLOYMENT_NAME app.kubernetes.io/maintenance-mode="true" --namespace $KUBERNETES_NAMESPACE --overwrite
# log "Application is in maintenance mode."

# --- Build Steps (if not pre-built) ---
# This section might be handled by a separate CI pipeline.
# log "Starting build process..."
# ./build-script.sh # Assuming you have a build script
# log "Build completed."

# --- Docker Image Steps (if applicable) ---
# log "Pulling latest Docker image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG..."
# docker pull "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" || error_exit "Failed to pull Docker image."
# log "Docker image pulled successfully."

# --- Deployment Steps ---
log "Starting deployment to Kubernetes..."

# 1. Update Kubernetes deployment with the new image
log "Updating Kubernetes deployment $KUBERNETES_DEPLOYMENT_NAME in namespace $KUBERNETES_NAMESPACE with image $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG..."
kubectl set image deployment/$KUBERNETES_DEPLOYMENT_NAME "$APP_NAME=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG" --namespace $KUBERNETES_NAMESPACE --record || error_exit "Failed to update Kubernetes deployment."
log "Kubernetes deployment update initiated."

# 2. Wait for the deployment to complete
log "Waiting for deployment rollout to complete..."
kubectl rollout status deployment/$KUBERNETES_DEPLOYMENT_NAME --namespace $KUBERNETES_NAMESPACE --timeout=5m || error_exit "Deployment rollout failed or timed out."
log "Deployment successfully rolled out."

# --- Post-deployment Steps ---
log "Starting post-deployment steps..."

# 1. (Optional) Run database migrations
# log "Running database migrations..."
# kubectl exec -n $KUBERNETES_NAMESPACE deployment/$KUBERNETES_DEPLOYMENT_NAME -- yarn db:migrate # Example for Node.js/Yarn
# log "Database migrations completed."

# 2. (Optional) Clear caches
# log "Clearing application caches..."
# kubectl exec -n $KUBERNETES_NAMESPACE deployment/$KUBERNETES_DEPLOYMENT_NAME -- yarn cache:clear # Example
# log "Caches cleared."

# 3. (Optional) Take application out of maintenance mode
# log "Taking application out of maintenance mode..."
# kubectl annotate deployment $KUBERNETES_DEPLOYMENT_NAME app.kubernetes.io/maintenance-mode- --namespace $KUBERNETES_NAMESPACE --overwrite
# log "Application is now live."

# 4. (Optional) Send notification
# ./scripts/send-notification.sh "Deployment of $APP_NAME version $DOCKER_IMAGE_TAG completed successfully."

log "Application deployment finished successfully!"
exit 0
