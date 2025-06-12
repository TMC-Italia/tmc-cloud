#!/bin/bash

# Network Configuration Script
# Configures network settings for TMC-Cloud nodes

set -e

source "$(dirname "$0")/common.sh"

# Configure static IP
configure_static_ip() {
    log "Configuring static IP address..."
  
    echo "Available network interfaces:"
    ip link show
  
    read -p "Enter the network interface name (e.g., eth0, ens33): " INTERFACE
    read -p "Enter the static IP address (e.g., 192.168.1.100): " IP_ADDRESS
    read -p "Enter the gateway IP (e.g., 192.168.1.1): " GATEWAY
    read -p "Enter DNS servers (e.g., 8.8.8.8,8.8.4.4): " DNS_SERVERS
  
    # Create netplan configuration
    sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOL
network:
  version: 2
  ethernets:
    ${INTERFACE}:
      dhcp4: false
      addresses:
        - ${IP_ADDRESS}/24
      gateway4: ${GATEWAY}
      nameservers:
        addresses: [${DNS_SERVERS//,/, }]
EOL
  
    # Apply network configuration
    sudo netplan apply
  
    info "Static IP configured: ${IP_ADDRESS}"
}

# Configure hostname
configure_hostname() {
    log "Configuring hostname..."
  
    read -p "Enter hostname for this node (e.g., k8s-master, k8s-worker1): " HOSTNAME
  
    # Set hostname
    sudo hostnamectl set-hostname ${HOSTNAME}
  
    # Update /etc/hosts
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\\t${HOSTNAME}/" /etc/hosts
  
    info "Hostname configured: ${HOSTNAME}"
}

# Configure hosts file
configure_hosts() {
    log "Configuring /etc/hosts file..."
  
    # Add cluster nodes to hosts file
    sudo tee -a /etc/hosts > /dev/null <<EOL

# TMC-Cloud cluster nodes
192.168.1.100   k8s-master
192.168.1.101   k8s-worker1
192.168.1.102   k8s-worker2
192.168.1.103   k8s-storage
EOL
  
    info "Hosts file updated"
}

# Main execution
main() {
    echo "===="
    echo "  TMC-Cloud Network Configuration"
    echo "===="
    echo
  
    configure_static_ip
    configure_hostname
    configure_hosts
  
    log "Network configuration completed!"
    info "Please reboot the system to ensure all changes take effect."
}

main "$@"