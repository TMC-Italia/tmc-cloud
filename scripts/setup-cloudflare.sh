#!/bin/bash

# On-Premises Cloud Infrastructure - Cloudflare Tunnel Setup
# Enhanced script for public service exposure with OAuth integration
# Author: Based on project documentation
# Version: 2.0

source "$(dirname "$0")/common.sh"

set -e  # Exit on any error

# Configuration
CLOUDFLARED_CONFIG_DIR="/etc/cloudflared"
TUNNEL_CONFIG_FILE="$CLOUDFLARED_CONFIG_DIR/config.yml"
LOG_FILE="$HOME/on-premises-cloud/logs/cloudflare-setup.log"
TUNNEL_NAME="on-premises-k8s"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running with sudo privileges
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 cloudflare.com &>/dev/null; then
        error "Cannot reach Cloudflare. Please check your internet connection."
    fi
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check if domain is provided
    if [ -z "$DOMAIN" ]; then
        warn "DOMAIN environment variable not set. You'll need to configure DNS manually."
    fi
    
    info "Prerequisites check passed ✓"
}

# Install Cloudflared
install_cloudflared() {
    log "Installing Cloudflared..."
    
    # Check if already installed
    if command -v cloudflared &>/dev/null; then
        warn "Cloudflared is already installed. Checking version..."
        cloudflared version | tee -a "$LOG_FILE"
        return 0
    fi
    
    # Download and install cloudflared
    ARCH=$(dpkg --print-architecture)
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    
    wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb
    rm /tmp/cloudflared.deb
    
    # Verify installation
    if ! command -v cloudflared &>/dev/null; then
        error "Cloudflared installation failed"
    fi
    
    info "Cloudflared installed successfully ✓"
}

# Authenticate with Cloudflare
authenticate_cloudflare() {
    log "Authenticating with Cloudflare..."
    
    # Check if already authenticated
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        warn "Already authenticated with Cloudflare"
        return 0
    fi
    
    info "Please complete the authentication in your browser..."
    cloudflared tunnel login
    
    # Verify authentication
    if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
        error "Cloudflare authentication failed"
    fi
    
    info "Cloudflare authentication successful ✓"
}

# Create tunnel
create_tunnel() {
    log "Creating Cloudflare tunnel..."
    
    # Check if tunnel already exists
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        warn "Tunnel '$TUNNEL_NAME' already exists"
        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    else
        # Create new tunnel
        cloudflared tunnel create "$TUNNEL_NAME"
        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    fi
    
    if [ -z "$TUNNEL_ID" ]; then
        error "Failed to create or find tunnel"
    fi
    
    info "Tunnel ID: $TUNNEL_ID ✓"
}

# Configure tunnel
configure_tunnel() {
    log "Configuring tunnel..."
    
    # Create configuration directory
    sudo mkdir -p "$CLOUDFLARED_CONFIG_DIR"
    
    # Create tunnel configuration
    cat > /tmp/cloudflared-config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  # GitLab
  - hostname: gitlab.${DOMAIN:-example.com}
    service: http://192.168.1.101:30080
    originRequest:
      noTLSVerify: true
  
  # Grafana Monitoring
  - hostname: grafana.${DOMAIN:-example.com}
    service: http://192.168.1.100:30300
    originRequest:
      noTLSVerify: true
  
  # Kubernetes Dashboard
  - hostname: k8s.${DOMAIN:-example.com}
    service: https://192.168.1.100:6443
    originRequest:
      noTLSVerify: true
  
  # Prometheus
  - hostname: prometheus.${DOMAIN:-example.com}
    service: http://192.168.1.100:30900
    originRequest:
      noTLSVerify: true
  
  # Default catch-all (required)
  - service: http_status:404

# Optional: Enable metrics
metrics: 0.0.0.0:8080
EOF
    
    # Move configuration to system directory
    sudo mv /tmp/cloudflared-config.yml "$TUNNEL_CONFIG_FILE"
    
    # Copy tunnel credentials
    sudo cp "$HOME/.cloudflared/$TUNNEL_ID.json" "$CLOUDFLARED_CONFIG_DIR/"
    
    # Set proper permissions
    sudo chown root:root "$CLOUDFLARED_CONFIG_DIR"/*
    sudo chmod 600 "$CLOUDFLARED_CONFIG_DIR"/*
    
    info "Tunnel configuration created ✓"
}

# Setup DNS routes
setup_dns_routes() {
    log "Setting up DNS routes..."
    
    if [ -z "$DOMAIN" ]; then
        warn "DOMAIN not set. Skipping automatic DNS setup."
        info "Manual DNS setup required. Use these commands:"
        echo "  cloudflared tunnel route dns $TUNNEL_NAME gitlab.yourdomain.com"
        echo "  cloudflared tunnel route dns $TUNNEL_NAME grafana.yourdomain.com"
        echo "  cloudflared tunnel route dns $TUNNEL_NAME k8s.yourdomain.com"
        echo "  cloudflared tunnel route dns $TUNNEL_NAME prometheus.yourdomain.com"
        return 0
    fi
    
    # Create DNS routes
    local services=("gitlab" "grafana" "k8s" "prometheus")
    
    for service in "${services[@]}"; do
        local hostname="${service}.${DOMAIN}"
        if cloudflared tunnel route dns "$TUNNEL_NAME" "$hostname"; then
            info "DNS route created for $hostname ✓"
        else
            warn "Failed to create DNS route for $hostname"
        fi
    done
}

# Install as system service
install_service() {
    log "Installing Cloudflared as system service..."
    
    # Install service
    sudo cloudflared service install
    
    # Enable and start service
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared
    
    # Check service status
    if sudo systemctl is-active --quiet cloudflared; then
        info "Cloudflared service installed and running ✓"
    else
        error "Failed to start Cloudflared service"
    fi
}

# Create management scripts
create_management_scripts() {
    log "Creating Cloudflare management scripts..."
    
    # Create scripts directory
    mkdir -p "$HOME/on-premises-cloud/tools/cloudflare"
    
    # Status script
    cat > "$HOME/on-premises-cloud/tools/cloudflare/status.sh" <<EOF
#!/bin/bash
echo "=== Cloudflare Tunnel Status ==="
sudo systemctl status cloudflared --no-pager
echo
echo "=== Tunnel List ==="
cloudflared tunnel list
echo
echo "=== Tunnel Info ==="
cloudflared tunnel info $TUNNEL_NAME
echo
echo "=== Service Logs (last 20 lines) ==="
sudo journalctl -u cloudflared -n 20 --no-pager
EOF
    
    # Restart script
    cat > "$HOME/on-premises-cloud/tools/cloudflare/restart.sh" <<EOF
#!/bin/bash
echo "Restarting Cloudflare Tunnel..."
sudo systemctl restart cloudflared
sleep 3
sudo systemctl status cloudflared --no-pager
EOF
    
    # Update configuration script
    cat > "$HOME/on-premises-cloud/tools/cloudflare/update-config.sh" <<EOF
#!/bin/bash
echo "Updating Cloudflare Tunnel configuration..."
sudo systemctl stop cloudflared
echo "Edit the configuration file: $TUNNEL_CONFIG_FILE"
echo "Press Enter when done..."
read
sudo systemctl start cloudflared
sudo systemctl status cloudflared --no-pager
EOF
    
    # Make scripts executable
    chmod +x "$HOME/on-premises-cloud/tools/cloudflare/"*.sh
    
    info "Management scripts created ✓"
}

# Setup OAuth access policies
setup_oauth_policies() {
    log "Setting up OAuth access policies..."
    
    info "OAuth Configuration Instructions:"
    echo
    echo "1. Go to Cloudflare Zero Trust Dashboard:"
    echo "   https://one.dash.cloudflare.com/"
    echo
    echo "2. Navigate to Access > Applications"
    echo
    echo "3. Create applications for each service:"
    echo "   - GitLab: gitlab.${DOMAIN:-yourdomain.com}"
    echo "   - Grafana: grafana.${DOMAIN:-yourdomain.com}"
    echo "   - Kubernetes: k8s.${DOMAIN:-yourdomain.com}"
    echo "   - Prometheus: prometheus.${DOMAIN:-yourdomain.com}"
    echo
    echo "4. Configure access policies (e.g., email domain, specific users)"
    echo
    echo "5. Enable session duration and other security settings"
    echo
    warn "OAuth setup requires manual configuration in Cloudflare dashboard"
}

# Display connection information
show_connection_info() {
    log "Displaying connection information..."
    
    echo
    echo "=================================================="
    echo "  Cloudflare Tunnel Setup Complete"
    echo "=================================================="
    echo
    
    info "Tunnel Name: $TUNNEL_NAME"
    info "Tunnel ID: $TUNNEL_ID"
    info "Configuration: $TUNNEL_CONFIG_FILE"
    
    echo
    info "Configured Services:"
    if [ -n "$DOMAIN" ]; then
        echo "  GitLab: https://gitlab.$DOMAIN"
        echo "  Grafana: https://grafana.$DOMAIN"
        echo "  Kubernetes: https://k8s.$DOMAIN"
        echo "  Prometheus: https://prometheus.$DOMAIN"
    else
        echo "  Configure DNS manually for your domain"
    fi
    
    echo
    info "Management commands:"
    echo "  Status: $HOME/on-premises-cloud/tools/cloudflare/status.sh"
    echo "  Restart: $HOME/on-premises-cloud/tools/cloudflare/restart.sh"
    echo "  Update config: $HOME/on-premises-cloud/tools/cloudflare/update-config.sh"
    
    echo
    warn "IMPORTANT NOTES:"
    echo "  1. Configure OAuth policies in Cloudflare Zero Trust dashboard"
    echo "  2. Services are exposed publicly - ensure proper authentication"
    echo "  3. Monitor tunnel metrics at http://localhost:8080/metrics"
    echo "  4. Check service logs: sudo journalctl -u cloudflared -f"
    
    echo
    info "Next steps:"
    echo "  1. Configure OAuth access policies"
    echo "  2. Test external access to services"
    echo "  3. Set up monitoring and alerting"
    echo "  4. Configure SSL certificates if needed"
}

# Main execution
main() {
    echo "=================================================="
    echo "  Cloudflare Tunnel Setup for On-Premises Cloud"
    echo "=================================================="
    echo
    
    # Check for domain parameter
    if [ -n "$1" ]; then
        DOMAIN="$1"
        info "Using domain: $DOMAIN"
    fi
    
    check_prerequisites
    install_cloudflared
    authenticate_cloudflare
    create_tunnel
    configure_tunnel
    setup_dns_routes
    install_service
    create_management_scripts
    setup_oauth_policies
    show_connection_info
    
    log "Cloudflare Tunnel setup completed successfully!"
}

# Run main function
main "$@"