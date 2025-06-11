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
LOG_FILE="$HOME/on-premises-cloud/logs/cloudflare-setup.log" # Assuming common.sh or user creates ~/on-premises-cloud/logs

DEFAULT_TUNNEL_NAME="on-premises-k8s"
TUNNEL_NAME="" # Will be set by user input in check_prerequisites

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Prompt for Tunnel Name
    read -r -p "Enter a name for your Cloudflare Tunnel [${DEFAULT_TUNNEL_NAME}]: " USER_TUNNEL_NAME
    TUNNEL_NAME="${USER_TUNNEL_NAME:-$DEFAULT_TUNNEL_NAME}"
    if [[ ! "$TUNNEL_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        error "Invalid Tunnel Name. Use alphanumeric characters and hyphens only."
        # exit 1 # Or handle error appropriately
    fi
    info "Using Tunnel Name: $TUNNEL_NAME"
    
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
        warn "Already authenticated with Cloudflare (cert.pem found)."
        info "For fully headless setup in the future, ensure cert.pem is pre-placed in ~/.cloudflared/ and this login step will be skipped."
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
    
    # Create tunnel configuration content
    # Using placeholders \${TUNNEL_ID_PLACEHOLDER} and \${DOMAIN_PLACEHOLDER} to be replaced by sed
    # This avoids issues with shell expansion within the heredoc if $TUNNEL_ID or $DOMAIN contained special characters.
    local TUNNEL_CONFIG_CONTENT
    TUNNEL_CONFIG_CONTENT=$(cat <<EOF
# config.yml
# Tunnel ID will be substituted by the script.
# Credentials file path will be substituted by the script.
tunnel: \${TUNNEL_ID_PLACEHOLDER}
credentials-file: /etc/cloudflared/\${TUNNEL_ID_PLACEHOLDER}.json

ingress:
  # Example: Expose a service running on http://localhost:8000
  # - hostname: myapp.\${DOMAIN_PLACEHOLDER}
  #   service: http://localhost:8000
  #
  # --- IMPORTANT ---
  # 1. Add your services here by uncommenting and modifying the example or adding new entries.
  # 2. Ensure your origin services use VALID TLS CERTIFICATES if they are HTTPS.
  #    cloudflared will attempt to verify them by default.
  # 3. For HTTP origins, cloudflared provides TLS termination at the Cloudflare edge.
  # 4. If you MUST use self-signed certificates for a specific HTTPS origin AND understand the risk,
  #    you can add 'originRequest:'
  #                '  noTLSVerify: true'
  #    under that specific service entry. This is NOT recommended for production.
  # ---
  # Default catch-all rule (required to prevent Cloudflare from serving a generic error page).
  # This should be the last rule in the ingress list.
  - service: http_status:404

# Cloudflared configuration runs from /etc/cloudflared/ directory by default when run as a service.
# Log file location is typically managed by systemd (e.g., journalctl -u cloudflared).
# Autoupdates for cloudflared daemon are usually managed by the system package manager (apt).
metrics: localhost:8081 # Changed from 0.0.0.0:8080 to localhost:8081 for security and to avoid port conflicts.
EOF
)
    
    # Replace placeholders
    TUNNEL_CONFIG_CONTENT="${TUNNEL_CONFIG_CONTENT//\\${TUNNEL_ID_PLACEHOLDER}/$TUNNEL_ID}"
    # If DOMAIN is not set, use "example.com" as a placeholder in the config comments
    TUNNEL_CONFIG_CONTENT="${TUNNEL_CONFIG_CONTENT//\\${DOMAIN_PLACEHOLDER}/${DOMAIN:-example.com}}"

    # Write configuration to system directory
    echo "$TUNNEL_CONFIG_CONTENT" | sudo tee "$TUNNEL_CONFIG_FILE" > /dev/null

    warn "SECURITY WARNING: 'noTLSVerify: true' has been REMOVED from the default configuration examples."
    warn "Cloudflared will now VERIFY TLS certificates for your origin HTTPS services by default."
    info "Ensure your internal services use valid, trusted TLS certificates if they are HTTPS, or serve them over HTTP if TLS is handled at the Cloudflare edge."
    info "Edit $TUNNEL_CONFIG_FILE to add your services and manage TLS verification settings (noTLSVerify) per service if absolutely necessary and risks are understood."
    
    # Copy tunnel credentials
    sudo cp "$HOME/.cloudflared/$TUNNEL_ID.json" "$CLOUDFLARED_CONFIG_DIR/"
    
    # Set proper permissions
    sudo chown root:root "$CLOUDFLARED_CONFIG_DIR"/*
    sudo chmod 600 "$CLOUDFLARED_CONFIG_DIR"/*
    
    info "Tunnel configuration created at $TUNNEL_CONFIG_FILE ✓"
}

# Setup DNS routes (now instructional)
setup_dns_routes() {
    log "Setting up DNS routes (Instructional)..."

    info "DNS routes need to be configured MANUALLY for each hostname you define in $TUNNEL_CONFIG_FILE."
    info "Once you have added hostnames to your $TUNNEL_CONFIG_FILE (e.g., myapp.${DOMAIN:-yourdomain.com}),"
    info "you can create the DNS record for it using a command like this:"
    info "  cloudflared tunnel route dns $TUNNEL_NAME myapp.${DOMAIN:-yourdomain.com}"
    warn "This script will NOT automatically create DNS routes anymore due to the dynamic nature of ingress configuration."
    info "Please add DNS routes manually for each service you expose via the tunnel."
    if [ -z "$DOMAIN" ]; then
        warn "Remember, the DOMAIN variable was not set, so ensure you use your correct domain when creating DNS routes."
    fi
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
    # TUNNEL_NAME is a global variable in the main script, set during check_prerequisites
    cat > "$HOME/on-premises-cloud/tools/cloudflare/status.sh" <<EOF
#!/bin/bash
# This script uses the Tunnel Name configured during 'setup-cloudflare.sh'.
# If you've created tunnels with different names, you might need to adjust this.
TUNNEL_NAME_FOR_SCRIPT="${TUNNEL_NAME}"

echo "=== Cloudflare Tunnel Status for: \$TUNNEL_NAME_FOR_SCRIPT ==="
sudo systemctl status cloudflared --no-pager
echo
echo "=== Tunnel List (all tunnels on this account) ==="
cloudflared tunnel list
echo
echo "=== Detailed Info for: \$TUNNEL_NAME_FOR_SCRIPT ==="
cloudflared tunnel info "\$TUNNEL_NAME_FOR_SCRIPT"
echo
echo "=== Service Logs (last 20 lines for cloudflared.service) ==="
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
    echo "3. Create applications for each service you have configured in $TUNNEL_CONFIG_FILE."
    echo "   For example, if you configured 'myapp.${DOMAIN:-yourdomain.com}', create an application for that hostname."
    echo
    echo "4. Configure access policies for each application (e.g., based on email domain, specific users, etc.)."
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
    info "Tunnel ID: ${TUNNEL_ID:-Not Created Yet}" # TUNNEL_ID is set in create_tunnel
    info "Configuration file: $TUNNEL_CONFIG_FILE"
    
    echo
    info "Configured Services: (Please refer to your $TUNNEL_CONFIG_FILE)"
    info "Remember to manually add DNS routes for each hostname you configure."
    
    echo
    info "Management commands:"
    echo "  Status: $HOME/on-premises-cloud/tools/cloudflare/status.sh"
    echo "  Restart: $HOME/on-premises-cloud/tools/cloudflare/restart.sh"
    echo "  Update config: $HOME/on-premises-cloud/tools/cloudflare/update-config.sh"
    
    echo
    warn "IMPORTANT NOTES:"
    echo "  1. Configure OAuth access policies in Cloudflare Zero Trust for your exposed hostnames."
    echo "  2. Ensure services defined in $TUNNEL_CONFIG_FILE are running and accessible from this machine."
    echo "  3. Monitor tunnel metrics at http://localhost:8081/metrics (if enabled and default port used)."
    echo "  4. Check service logs: sudo journalctl -u cloudflared -f"
    
    echo
    info "Next steps:"
    echo "  1. Edit $TUNNEL_CONFIG_FILE to define your ingress rules."
    echo "  2. For each hostname in your config, create a DNS route: cloudflared tunnel route dns $TUNNEL_NAME <hostname>"
    echo "  3. Configure OAuth access policies in Cloudflare Zero Trust dashboard for each application."
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