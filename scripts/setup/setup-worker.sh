#!/bin/bash

# Kubernetes Worker Node Setup Script

source "$(dirname "$0")/common.sh"

# Join cluster
join_cluster() {
    log "Joining Kubernetes cluster..."
  
    echo "Please enter the kubeadm join command from the master node:"
    read -p "Join command: " JOIN_COMMAND
  
    # Execute join command
    sudo ${JOIN_COMMAND}
  
    info "Successfully joined the cluster"
}

# Main execution
main() {
    echo "===="
    echo "  Kubernetes Worker Node Setup"
    echo "===="
    echo
  
    join_cluster
  
    log "Worker node setup completed!"
}

main "$@"