#!/bin/bash

# Backup System Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Install Velero
install_velero() {
    log "Installing Velero..."
  
    # Download Velero
    VELERO_VERSION="v1.12.0"
    wget https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-x64.tar.gz
    tar -xzf velero-${VELERO_VERSION}-linux-x64.tar.gz
    sudo mv velero-${VELERO_VERSION}-linux-x64/velero /usr/local/bin/
    rm -rf velero-${VELERO_VERSION}-linux-x64*
  
    info "Velero installed"
}

# Install MinIO
install_minio() {
    log "Installing MinIO..."
  
    # Add MinIO Helm repository
    helm repo add minio https://charts.min.io/
    helm repo update
  
    # Install MinIO
    helm install minio minio/minio \
        --namespace minio-system \
        --create-namespace \
        --set rootUser=admin \
        --set rootPassword=minio123 \
        --set persistence.size=100Gi
  
    info "MinIO installed"
}

# Configure Velero with MinIO
configure_velero() {
    log "Configuring Velero with MinIO..."
  
    # Create credentials file
    cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id = admin
aws_secret_access_key = minio123
EOF
  
    # Install Velero with MinIO backend
    velero install \
        --provider aws \
        --plugins velero/velero-plugin-for-aws:v1.8.0 \
        --bucket velero \
        --secret-file /tmp/credentials-velero \
        --use-volume-snapshots=false \
        --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.minio-system.svc.cluster.local:9000
  
    # Clean up credentials file
    rm /tmp/credentials-velero
  
    info "Velero configured with MinIO"
}

# Main execution
main() {
    echo "===="
    echo "  Backup System Setup"
    echo "===="
    echo
  
    install_velero
    install_minio
    configure_velero
  
    log "Backup system setup completed!"
  
    echo
    info "Create your first backup:"
    echo "  velero backup create initial-backup"
    echo
}

main "$@"