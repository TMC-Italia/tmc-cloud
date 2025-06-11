#!/bin/bash

# On-Premises Cloud Infrastructure - Tailscale VPN Setup
# Enhanced script for secure remote access configuration
# Author: Based on project documentation
# Version: 2.0

source "$(dirname "$0")/common.sh"

set -e  # Exit on any error

# Configuration
# TAILSCALE_CONFIG_DIR removed as it's not standard. Tailscale manages its state in /var/lib/tailscale.
LOG_FILE="$HOME/on-premises-cloud/logs/tailscale-setup.log" # Assuming common.sh or user creates ~/on-premises-cloud/logs

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
    log "Configuring Tailscale system settings..."

    # Enable IP forwarding for subnet routing (idempotent)
    log "Ensuring IP forwarding is enabled in sysctl.conf..."
    grep -qxF 'net.ipv4.ip_forward = 1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
    grep -qxF 'net.ipv6.conf.all.forwarding = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf

    log "Applying sysctl changes..."
    sudo sysctl -p # Apply changes from /etc/sysctl.conf and other sysctl config files

    warn "IP forwarding has been enabled. This allows the node to act as a subnet router if advertising routes. Ensure this is intended and secured via Tailscale ACLs."

    # Configure firewall rules for Tailscale
    configure_firewall

    info "Tailscale system configuration completed ✓"
}

# Configure firewall for Tailscale using UFW
configure_firewall() {
    log "Configuring UFW firewall for Tailscale..."

    if ! command -v ufw &> /dev/null; then
        warn "UFW command not found. Skipping UFW configuration for Tailscale. Manual firewall configuration may be required."
        return
    fi

    # Allow all traffic on the tailscale0 interface (Tailscale handles encryption and authentication)
    log "Allowing all traffic in and out on tailscale0 interface..."
    sudo ufw allow in on tailscale0 comment 'Allow all incoming traffic on Tailscale interface'
    sudo ufw allow out on tailscale0 comment 'Allow all outgoing traffic on Tailscale interface'

    # Allow Tailscale's discovery/NAT traversal UDP port
    log "Allowing Tailscale NAT traversal (41641/udp)..."
    sudo ufw allow 41641/udp comment 'Allow Tailscale NAT traversal (UDP)'

    # No need for netfilter-persistent save with UFW as UFW manages its own rules persistence.
    # Ensure UFW is enabled (usually done in setup-environment.sh)
    if sudo ufw status | grep -q "Status: active"; then
        info "UFW is active. Rules for Tailscale applied."
    else
        warn "UFW is not active. Tailscale rules have been added, but UFW needs to be enabled for them to take effect."
        warn "You can enable UFW with: sudo ufw enable"
    fi

    info "Configured UFW rules for Tailscale. Ensure UFW is enabled and running."
}

# Start Tailscale with options
start_tailscale() {
    log "Starting Tailscale..."

    # Check if already running
    if sudo tailscale status &>/dev/null; then
        warn "Tailscale is already running or configured. To reconfigure, you might need to run 'sudo tailscale logout' first or 'sudo tailscale down'."
        sudo tailscale status | tee -a "$LOG_FILE"
        # Consider if script should exit or offer to logout/reset if already running. For now, just warn.
        # return 0
    fi

    # --- Auth Key Logic ---
    read -r -p "Use Tailscale auth key for headless login? (y/N): " USE_AUTH_KEY
    AUTH_KEY_PARAM=""
    if [[ "$USE_AUTH_KEY" == "y" || "$USE_AUTH_KEY" == "Y" ]]; then
        read -r -s -p "Enter Tailscale Auth Key: " TAILSCALE_AUTH_KEY; echo
        if [ -z "$TAILSCALE_AUTH_KEY" ]; then
            error "Auth key cannot be empty if selected. Aborting."
            return 1
        fi
        warn "Ensure this auth key is handled securely. Consider using ephemeral or pre-authorized keys for servers."
        AUTH_KEY_PARAM="--authkey=${TAILSCALE_AUTH_KEY}"
    else
        info "Proceeding with interactive login. A browser window or URL will be provided by Tailscale for authentication."
    fi

    # --- Advertised Routes Logic ---
    read -r -p "Enter comma-separated subnets to advertise (e.g., 192.168.1.0/24,10.0.1.0/24) or leave empty: " ADVERTISE_ROUTES_INPUT
    ROUTES_PARAM=""
    if [ -n "$ADVERTISE_ROUTES_INPUT" ]; then
        # Basic validation for comma-separated list (does not validate CIDR format itself)
        if [[ ! "$ADVERTISE_ROUTES_INPUT" =~ ^([0-9a-fA-F.:/]+,?)+$ ]]; then
            error "Invalid format for advertised routes. Should be comma-separated CIDRs (e.g., 192.168.1.0/24,10.0.1.0/24)."
            return 1
        fi
        ROUTES_PARAM="--advertise-routes=${ADVERTISE_ROUTES_INPUT}"
        info "Will attempt to advertise routes: ${ADVERTISE_ROUTES_INPUT}"
    else
        info "No subnets will be advertised by this node."
    fi

    # --- Hostname Logic ---
    DEFAULT_TS_HOSTNAME="$(hostname)-k8s"
    read -r -p "Enter Tailscale device hostname [${DEFAULT_TS_HOSTNAME}]: " TS_HOSTNAME_INPUT
    TS_HOSTNAME="${TS_HOSTNAME_INPUT:-$DEFAULT_TS_HOSTNAME}"
    HOSTNAME_PARAM="--hostname=${TS_HOSTNAME}"
    info "Tailscale device hostname will be set to: ${TS_HOSTNAME}"

    # --- Assemble and run tailscale up ---
    CMD_BASE="sudo tailscale up"
    CMD_ARGS=""
    if [ -n "$AUTH_KEY_PARAM" ]; then CMD_ARGS="$CMD_ARGS $AUTH_KEY_PARAM"; fi
    if [ -n "$ROUTES_PARAM" ]; then CMD_ARGS="$CMD_ARGS $ROUTES_PARAM"; fi
    # --accept-routes: Allows this node to receive routes advertised by other nodes in the tailnet.
    # --accept-dns=false: Prevents Tailscale from overriding local DNS settings (MagicDNS). Set to true if you want to use Tailscale's MagicDNS.
    CMD_ARGS="$CMD_ARGS --accept-routes --accept-dns=false $HOSTNAME_PARAM"

    info "Attempting to run: $CMD_BASE$CMD_ARGS" # CMD_ARGS will have a leading space if not empty

    # Using eval to correctly handle parameters that might be empty or contain spaces if not quoted properly (though here they should be fine)
    # However, direct execution is safer if possible. Let's try direct execution first.
    # If CMD_ARGS is empty, it's fine. If it has params, they are space-separated.
    if eval "$CMD_BASE $CMD_ARGS"; then
        info "Tailscale 'up' command executed."
    else
        error "Tailscale 'up' command failed. Check output above for details."
        return 1
    fi

    # Wait for connection (Tailscale usually handles this quickly)
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

    # Restart script - simplified to use --reset which reuses last 'up' settings.
    # TS_HOSTNAME is a global variable set during start_tailscale
    cat > "$HOME/on-premises-cloud/tools/tailscale/restart.sh" <<EOF
#!/bin/bash
# This script attempts to restart Tailscale using its last known configuration from setup,
# or by resetting to the configuration applied during the last successful 'tailscale up'.
# It includes the hostname set during the initial setup.
echo "Restarting Tailscale..."
sudo tailscale down
sleep 2
# Using --reset re-applies most of the last 'up' flags.
# We explicitly add --accept-routes, --accept-dns=false and the hostname for clarity/consistency.
# Ensure TS_HOSTNAME is correctly captured in the environment this script runs if it's not hardcoded.
# For this script, we embed the value of TS_HOSTNAME known at the time of creating this restart script.
sudo tailscale up --reset --accept-routes --accept-dns=false --hostname=${TS_HOSTNAME}
echo "Tailscale restart attempt completed."
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

    info "Current Tailscale IP (IPv4): $TAILSCALE_IP"
    # TS_HOSTNAME is set in start_tailscale. If this function is called independently, it might not be set.
    # For now, assuming it's available from the same script execution flow.
    info "Tailscale Hostname: ${TS_HOSTNAME:-$(hostname)-k8s}" # Use default if TS_HOSTNAME not set

    # Display advertised routes based on user input if available
    if [ -n "$ADVERTISE_ROUTES_INPUT" ]; then
        info "Advertised Routes: ${ADVERTISE_ROUTES_INPUT}"
    else
        info "Advertised Routes: None by this node"
    fi

    echo
    info "Management commands:"
    echo "  Status: sudo tailscale status"
    echo "  IP addresses: sudo tailscale ip -4 -6"
    echo "  Netcheck (diagnostics): sudo tailscale netcheck"
    echo "  Logout (disconnects and requires re-auth): sudo tailscale logout"
    echo "  Restart (using script): $HOME/on-premises-cloud/tools/tailscale/restart.sh"

    echo
    warn "IMPORTANT NOTES:"
    warn "CRITICAL SECURITY STEP: Configure Tailscale ACLs in your admin console (https://login.tailscale.com/admin/acls) to control which devices can connect to each other and to any advertised subnets. Do not skip this."
    if [ -n "$ADVERTISE_ROUTES_INPUT" ]; then
        echo "  - You are advertising routes: ${ADVERTISE_ROUTES_INPUT}."
        echo "  - You MUST approve these routes in the Tailscale admin console for them to be active."
    fi
    echo "  - Review Tailscale's 'Access Controls' documentation for best practices on securing your tailnet."
    echo "  - DNS acceptance is currently set to false (--accept-dns=false). If you want to use Tailscale's MagicDNS, re-run 'sudo tailscale up' with '--accept-dns=true'."

    echo
    info "Next steps:"
    echo "  1. Visit Tailscale Admin Console: https://login.tailscale.com/admin/machines to see this device."
    echo "  2. If you advertised routes, approve them from the 'Machines' page by finding this device and selecting 'Review subnet routes...'."
    echo "  3. Define or review your Tailscale ACLs: https://login.tailscale.com/admin/acls"
    echo "  4. Test connectivity from other devices in your tailnet to this node's Tailscale IP ($TAILSCALE_IP)."
    echo "  5. If advertising routes, test access to those subnets from other allowed devices in your tailnet."
}

# Global variable to store chosen Tailscale hostname for restart script
TS_HOSTNAME="" # Initialized globally

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