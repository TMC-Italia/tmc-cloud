#!/bin/bash

# CONFIGURATION FOR WORKER NODE:
# This script configures the current machine as a Kubernetes worker node.
# It requires the 'kubeadm join' command from the master node.
# Ensure network connectivity to the master node's IP and necessary ports.

# Kubernetes Worker Node Setup Script

source "$(dirname "$0")/common.sh"

# Join cluster
join_cluster() {
    log "Joining Kubernetes cluster..."

    # Confirm UFW status (should be configured by setup-environment.sh)
    log "Checking UFW status..."
    if sudo ufw status | grep -q "Status: active"; then
        info "UFW is active. Ensure necessary worker node ports are open (e.g., 10250/tcp for Kubelet, 30000-32767/tcp for NodePort services, plus CNI ports like Calico's 179/tcp and IP-in-IP)."
        info "These should have been configured by 'setup-environment.sh'."
    else
        warn "UFW is not active or status could not be determined. This might lead to connectivity issues with the master node or for pod networking."
        warn "It is highly recommended to ensure UFW is active and correctly configured before proceeding."
        # Optionally, prompt to continue or exit
        # read -p "UFW is not active. Continue anyway? (y/N): " choice
        # if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        #    error "Aborting due to inactive UFW."
        # fi
    fi

    warn "The 'kubeadm join' command contains sensitive information (e.g., token, discovery hash)."
    warn "Ensure you are transferring it to this worker node SECURELY (e.g., via SSH, encrypted pastebin, or direct console access)."
    warn "Do not expose it unnecessarily."

    echo -e "${BLUE}Please securely paste the full 'kubeadm join' command obtained from the master node:${NC}"
    # Using -r with read prevents backslash escapes from being interpreted.
    # Using -p for prompt.
    read -r -p "Join command: " JOIN_COMMAND

    if [ -z "$JOIN_COMMAND" ]; then
        error "Join command cannot be empty. Aborting."
        return 1
    fi

    # Execute join command
    log "Executing 'kubeadm join' command..."
    sudo ${JOIN_COMMAND}

    info "Successfully joined the cluster."
    info "Kubelet has been configured on this node. For advanced security auditing, Kubelet's configuration can be reviewed and customized via KubeletConfiguration resources, though default settings from 'kubeadm' are generally secure."
    info "Network Policies deployed on the master node (if any) will enforce traffic restrictions for pods scheduled on this worker node."
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