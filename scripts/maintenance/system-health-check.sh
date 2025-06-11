#!/bin/bash

# System Health Check Script

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

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check cluster health
check_cluster_health() {
    log "Checking cluster health..."
  
    # Check node status
    echo "Node Status:"
    kubectl get nodes
  
    # Check system pods
    echo "\nSystem Pods:"
    kubectl get pods -n kube-system
  
    # Check resource usage
    echo "\nResource Usage:"
    kubectl top nodes 2>/dev/null || echo "Metrics server not available"
  
    info "Cluster health check completed"
}

# Check storage
check_storage() {
    log "Checking storage..."
  
    # Check persistent volumes
    echo "Persistent Volumes:"
    kubectl get pv
  
    # Check persistent volume claims
    echo "\nPersistent Volume Claims:"
    kubectl get pvc --all-namespaces
  
    # Check disk usage on nodes
    echo "\nDisk Usage:"
    df -h
  
    info "Storage check completed"
}

# Main execution
main() {
    echo "===="
    echo "  TMC-Cloud System Health Check"
    echo "  $(date)"
    echo "===="
    echo
  
    check_cluster_health
    echo
    check_storage
  
    log "System health check completed!"
}

main "$@"