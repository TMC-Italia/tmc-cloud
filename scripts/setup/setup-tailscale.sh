#!/bin/bash

# On-Premises Cloud Infrastructure - Tailscale VPN Setup
# Enhanced script for secure remote access configuration
# Author: Based on project documentation
# Version: 2.0

source "$(dirname "$0")/common.sh"

set -e  # Exit on any error

# Configuration
TAILSCALE_CONFIG_DIR="/etc/tailscale"
LOG_FILE="$HOME/on-premises-cloud/logs/tailscale-setup.log"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running with sudo privileges
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges. Please run with sudo or ensure passwordless sudo is configured."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &>/dev/null; then
        error "No internet connectivity. Please check your network connection."
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    info "Prerequisites check passed ✓"
}

# Install Tailscale
install_tailscale() {
    log "Installing Tailscale..."
    
    # Check if already installed
    if command -v tailscale &>/dev/null; then
        warn "Tailscale is already installed. Checking version..."
        tailscale version | tee -a "$LOG_FILE"
        return 0
    fi
    
    # Download and install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    
    # Verify installation
    if ! command -v tailscale &>/dev/null; then
        error "Tailscale installation failed"
    fi
    
    info "Tailscale installed successfully ✓"
}

# Configure Tailscale
configure_tailscale() {
    log "Configuring Tailscale..."
    
    # Create configuration directory
    sudo mkdir -p "$TAILSCALE_CONFIG_DIR"
    
    # Enable IP forwarding for subnet routing
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    
    # Configure firewall rules for Tailscale
    configure_firewall
    
    info "Tailscale configuration completed ✓"
}

# Configure firewall for Tailscale
configure_firewall() {
    log "Configuring firewall for Tailscale..."
    
    # Allow Tailscale traffic
    sudo iptables -A INPUT -i tailscale0 -j ACCEPT
    sudo iptables -A OUTPUT -o tailscale0 -j ACCEPT
    
    # Allow Tailscale UDP port
    sudo iptables -A INPUT -p udp --dport 41641 -j ACCEPT
    
    # Save firewall rules
    if command -v netfilter-persistent &>/dev/null; then
        sudo netfilter-persistent save
    fi
    
    info "Firewall configured for Tailscale ✓"
}

# Start Tailscale with options
start_tailscale() {
    log "Starting Tailscale..."
    
    # Check if already running
    if sudo tailscale status &>/dev/null; then
        warn "Tailscale is already running"
        sudo tailscale status | tee -a "$LOG_FILE"
        return 0
    fi
    
    # Start Tailscale with subnet routing and accept routes
    info "Starting Tailscale with subnet routing enabled..."
    info "This will allow access to the entire local network (192.168.1.0/24)"
    
    # Enable subnet routing for the local network
    sudo tailscale up \
        --advertise-routes=192.168.1.0/24 \
        --accept-routes \
        --accept-dns=false \
        --hostname="$(hostname)-k8s"
    
    # Wait for connection
    sleep 5
    
    # Verify connection
    if sudo tailscale status &>/dev/null; then
        info "Tailscale started successfully ✓"
        sudo tailscale status | tee -a "$LOG_FILE"
    else
        error "Failed to start Tailscale"
    fi
}

# Enable Tailscale service
enable_service() {
    log "Enabling Tailscale service..."
    
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled
    
    # Check service status
    if sudo systemctl is-active --quiet tailscaled; then
        info "Tailscale service enabled and running ✓"
    else
        error "Failed to enable Tailscale service"
    fi
}

# Create Tailscale management scripts
create_management_scripts() {
    log "Creating Tailscale management scripts..."
    
    # Create scripts directory
    mkdir -p "$HOME/on-premises-cloud/tools/tailscale"
    
    # Status script
    cat > "$HOME/on-premises-cloud/tools/tailscale/status.sh" <<'EOF'
#!/bin/bash
echo "=== Tailscale Status ==="
sudo tailscale status
echo
echo "=== Tailscale IP ==="
sudo tailscale ip -4
echo
echo "=== Service Status ==="
sudo systemctl status tailscaled --no-pager
EOF
    
    # Restart script
    cat > "$HOME/on-premises-cloud/tools/tailscale/restart.sh" <<'EOF'
#!/bin/bash
echo "Restarting Tailscale..."
sudo tailscale down
sleep 2
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes --accept-dns=false
echo "Tailscale restarted"
EOF
    
    # Make scripts executable
    chmod +x "$HOME/on-premises-cloud/tools/tailscale/"*.sh
    
    info "Management scripts created ✓"
}

# Display connection information
show_connection_info() {
    log "Displaying connection information..."
    
    echo
    echo "=================================================="
    echo "  Tailscale VPN Setup Complete"
    echo "=================================================="
    echo
    
    # Get Tailscale IP
    TAILSCALE_IP=$(sudo tailscale ip -4 2>/dev/null || echo "Not available")
    
    info "Tailscale IP: $TAILSCALE_IP"
    info "Hostname: $(hostname)-k8s"
    info "Subnet routing: 192.168.1.0/24"
    
    echo
    info "Management commands:"
    echo "  Status: sudo tailscale status"
    echo "  IP: sudo tailscale ip"
    echo "  Logout: sudo tailscale logout"
    echo "  Restart: $HOME/on-premises-cloud/tools/tailscale/restart.sh"
    
    echo
    warn "IMPORTANT NOTES:"
    echo "  1. Subnet routing is enabled for 192.168.1.0/24"
    echo "  2. You may need to approve subnet routes in the Tailscale admin console"
    echo "  3. Other devices can access this entire network through Tailscale"
    echo "  4. DNS is disabled to avoid conflicts with local DNS"
    
    echo
    info "Next steps:"
    echo "  1. Check Tailscale admin console: https://login.tailscale.com/admin/machines"
    echo "  2. Approve subnet routes if needed"
    echo "  3. Test connectivity from remote devices"
    echo "  4. Configure other nodes with Tailscale"
}

# Main execution
main() {
    echo "=================================================="
    echo "  Tailscale VPN Setup for On-Premises Cloud"
    echo "=================================================="
    echo
    
    check_prerequisites
    install_tailscale
    configure_tailscale
    enable_service
    start_tailscale
    create_management_scripts
    show_connection_info
    
    log "Tailscale setup completed successfully!"
}

# Run main function
main "$@"