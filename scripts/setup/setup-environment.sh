#!/bin/bash

# CONFIGURATION FOR MULTI-LAPTOP DEPLOYMENT:
# This script is designed to be run on each laptop in your cluster.
# For values that might differ per node (e.g., specific IP addresses if not DHCP, roles):
# 1. Consider using environment variables to override defaults if scripts are adapted for this.
# 2. For more complex setups, you might use a simple config file (e.g., ~/tmc-cloud/configs/node-specific.env)
#    and source it, e.g.: source ~/tmc-cloud/configs/node-specific.env
# 3. The network configuration (IPs, CIDRs) is referenced from templates created by this script
#    (e.g., ~/tmc-cloud/configs/network/network-config.yaml). Ensure these are consistent with your plan.
# Scripts like setup-master.sh and setup-worker.sh will determine the node's role.

# On-Premises Cloud Infrastructure - Environment Setup Script
# This script prepares the system for Kubernetes cluster deployment with GitHub Actions CI/CD
# Author: Based on project documentation by Silvio Mario Pastori, Flavio Renzi, Marco Selva, Carmine Scacco
# Date: 2025-06-11
# Version: 2.0 - Updated for GitHub Actions integration

set -e  # Exit on any error

# Source common functions
source "$(dirname "$0")/common.sh"

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Check system requirements
check_system() {
    log "Checking system requirements..."

    # Check OS
    if ! grep -q "Ubuntu" /etc/os-release; then
        warn "This script is optimized for Ubuntu. Other distributions may require modifications."
    fi

    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        error "Minimum 2 CPU cores required. Found: $CPU_CORES"
    fi
    info "CPU cores: $CPU_CORES ✓"

    # Check RAM
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$RAM_GB" -lt 4 ]; then
        error "Minimum 4GB RAM required. Found: ${RAM_GB}GB"
    fi
    info "RAM: ${RAM_GB}GB ✓"

    # Check disk space
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$DISK_GB" -lt 50 ]; then
        error "Minimum 50GB free disk space required. Found: ${DISK_GB}GB"
    fi
    info "Free disk space: ${DISK_GB}GB ✓"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
}

# Install essential packages
install_essentials() {
    log "Installing essential packages..."
    # Note: iptables-persistent removed, ufw will be used.
    sudo apt install -y \\
        curl \\
        wget \\
        git \\
        vim \\
        htop \\
        net-tools \\
        nfs-common \\
        software-properties-common \\
        apt-transport-https \\
        ca-certificates \\
        gnupg \\
        lsb-release \\
        jq \\
        unzip \\
        tree \\
        rsync \\
        ufw \\
        fail2ban \\
        unattended-upgrades \\
        build-essential \\
        python3 \\
        python3-pip \\
        nodejs \\
        npm
}

# Install Docker
install_docker() {
    log "Installing Docker..."

    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker $USER

    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    info "Docker installed successfully"
}

# Install Kubernetes tools
install_kubernetes() {
    log "Installing Kubernetes tools..."

    # Add Kubernetes GPG key
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    # Add Kubernetes repository
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    # Install Kubernetes tools
    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl

    # Hold packages to prevent automatic updates
    sudo apt-mark hold kubelet kubeadm kubectl

    info "Kubernetes tools installed successfully"
}

# Install Helm
install_helm() {
    log "Installing Helm..."
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt update
    sudo apt install -y helm
    info "Helm installed successfully"
}

# Install GitHub CLI
install_github_cli() {
    log "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
    info "GitHub CLI installed successfully"
}

# Configure system settings
configure_system() {
    log "Configuring system settings..."

    # Hostname check and guidance for multi-node setups
    local current_hostname=$(hostname)
    if [[ "$current_hostname" == "ubuntu" || "$current_hostname" == "localhost" || "$current_hostname" == "linux" || "$current_hostname" == "debian" ]]; then
        warn "Your current hostname is generic: '$current_hostname'."
        warn "For a multi-node Kubernetes cluster, each node MUST have a unique and persistent hostname."
        info "It is highly recommended to set a unique hostname (e.g., k8s-master, k8s-worker1) before proceeding with cluster setup."
        info "You can set it using: sudo hostnamectl set-hostname <new-hostname>"
        info "After setting the hostname, update /etc/hosts to reflect the new hostname for 127.0.1.1 (if such an entry exists)."
        info "A reboot is typically required for all services to recognize the new hostname."
        info "This script will continue, but ensure hostnames are unique across all your laptops before initializing the cluster."
        # Optionally, you could add a read -p "Press [Enter] to acknowledge and continue..." here
    else
        info "Current hostname: '$current_hostname'. Ensure this is unique within your intended cluster."
    fi

    # Disable swap (required for Kubernetes)
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\\(.*\\)$/#\\1/g' /etc/fstab

    # Load required kernel modules
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Configure sysctl parameters
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sudo sysctl --system

    # Configure containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd

    info "System configuration completed"
}

# Setup UFW firewall rules
setup_ufw_firewall() {
    log "Configuring UFW firewall rules..."

    # Disable iptables-persistent if it's active, as we are using UFW
    if sudo systemctl is-active --quiet netfilter-persistent; then
        log "Disabling and stopping netfilter-persistent service..."
        sudo systemctl stop netfilter-persistent
        sudo systemctl disable netfilter-persistent
        # Remove old rules if they exist
        sudo rm -f /etc/iptables/rules.v4
        sudo rm -f /etc/iptables/rules.v6
    fi
    # An alternative to removing files is `sudo update-rc.d netfilter-persistent remove`

    # Ensure UFW is installed (should be from install_essentials)
    if ! command -v ufw &> /dev/null; then
        error "UFW command not found. Please ensure it's installed."
        return 1
    fi

    # Reset UFW to default state to ensure a clean setup (optional, can be disruptive)
    # Consider if this is too aggressive. For now, we'll add rules without a hard reset.
    # sudo ufw --force reset

    # Set default policies
    log "Setting UFW default policies: deny incoming, allow outgoing, deny routed."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default deny routed # Important for security if not acting as a router

    # Allow essential traffic
    log "Allowing SSH (port 22)..."
    sudo ufw allow ssh # Equivalent to allow 22/tcp

    log "Allowing HTTP (port 80) and HTTPS (port 443)..."
    sudo ufw allow http  # 80/tcp
    sudo ufw allow https # 443/tcp

    # Allow Kubernetes specific ports
    # Master node specific ports (can be applied to all nodes for simplicity in many setups)
    log "Allowing Kubernetes API server (6443/tcp) and etcd (2379:2380/tcp)..."
    sudo ufw allow 6443/tcp comment 'Kubernetes API Server'
    sudo ufw allow 2379:2380/tcp comment 'etcd client and peer'

    # Worker/common Kubernetes ports
    log "Allowing Kubelet (10250/tcp) and NodePort services (30000:32767/tcp)..."
    sudo ufw allow 10250/tcp comment 'Kubelet API'
    sudo ufw allow 30000:32767/tcp comment 'Kubernetes NodePort Services'

    # Allow Calico CNI ports (adjust if using a different CNI)
    # BGP for Calico
    log "Allowing Calico BGP (179/tcp)..."
    sudo ufw allow 179/tcp comment 'Calico BGP'
    # IP-in-IP (protocol 4). UFW needs modules loaded for this.
    # Ensure /etc/default/ufw has IPT_MODULES containing at least 'ip_tables ip6_tables nf_nat nf_conntrack ip_set ipip'
    # This rule might require manual check/setup of /etc/default/ufw.
    log "Attempting to load 'ipip' kernel module for Calico."
    sudo modprobe ipip
    log "Allowing Calico IP-in-IP (protocol ipip). Ensure 'ipip' module is loaded and configured in /etc/default/ufw for persistence if not already."
    sudo ufw allow proto ipip comment 'Calico IP-in-IP'
    # VXLAN for Calico (if used instead of IP-in-IP)
    # sudo ufw allow 4789/udp comment 'Calico VXLAN'
    # Typha for Calico (if used)
    # sudo ufw allow 5473/tcp comment 'Calico Typha'
    log "Note: Calico CNI requirements can vary. Review Calico documentation for specific port needs for your setup (e.g., VXLAN, Typha)."

    # Allow Flannel CNI ports (example, commented out as Calico is primary for this project)
    # log "Allowing Flannel VXLAN (8285/udp, 8472/udp)..."
    # sudo ufw allow 8285/udp comment 'Flannel VXLAN (control)'
    # sudo ufw allow 8472/udp comment 'Flannel VXLAN (data)'

    # Allow internal cluster communication (replace with your actual internal LAN/VPN subnet)
    # This is crucial for inter-node communication.
    # Example: if your nodes are on 192.168.1.0/24
    INTERNAL_LAN_SUBNET="192.168.1.0/24" # Make this configurable or detect if possible
    log "Allowing all traffic from internal LAN subnet ${INTERNAL_LAN_SUBNET}..."
    sudo ufw allow from "${INTERNAL_LAN_SUBNET}" comment 'Internal LAN traffic'
    # Consider also allowing traffic from Pod and Service CIDRs if necessary, though often handled by CNI/kube-proxy rules directly in iptables.
    # Example: POD_CIDR="10.244.0.0/16"; sudo ufw allow from "${POD_CIDR}" comment 'Pod Network'
    # Example: SERVICE_CIDR="10.96.0.0/12"; sudo ufw allow from "${SERVICE_CIDR}" comment 'Service Network'

    # Enable UFW logging
    log "Enabling UFW logging..."
    sudo ufw logging on # Options: low, medium, high, full

    # Enable UFW
    # The --force option is used to enable UFW without prompting if done via script.
    log "Enabling UFW..."
    yes | sudo ufw enable || true # `yes |` handles the y/n prompt. `|| true` prevents exit if ufw is already enabled.
    # A more robust way: sudo ufw status | grep -q inactive && yes | sudo ufw enable

    sudo ufw status verbose
    info "UFW firewall configured and enabled."
}

# Configure automatic system updates
configure_automatic_updates() {
    log "Configuring automatic updates (unattended-upgrades)..."

    # Ensure the package is installed
    if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
        warn "unattended-upgrades package is not installed. Skipping configuration."
        return 1
    fi

    # Create/overwrite the auto-upgrades configuration file
    cat <<EOF | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    log "Created /etc/apt/apt.conf.d/20auto-upgrades"

    # Create/overwrite a more detailed unattended-upgrades configuration
    # This is a basic configuration. Users might want to customize it further,
    # especially regarding automatic reboots or specific package handling.
    cat <<EOF | sudo tee /etc/apt/apt.conf.d/50unattended-upgrades
// Automatically upgrade packages from these origin patterns
Unattended-Upgrade::Allowed-Origins {
    // Ubuntu main and security updates
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    // Extended Security Maintenance (ESM) - if applicable
    // "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    // "\${distro_id}ESMInfra:\${distro_codename}-infra-security";
    // Backports (optional, use with caution)
    // "\${distro_id}:\${distro_codename}-backports";
};

// List of packages to not update
Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6";
    // "docker-ce"; "docker-ce-cli"; "containerd.io"; # If managing Docker versions manually
    "kubeadm"; "kubelet"; "kubectl"; # Kubernetes components are often version-pinned
};

// Automatically reboot_with_delay if required, and if the user is not logged in.
// Set to "false" if you don't want automatic reboots.
Unattended-Upgrade::Automatic-Reboot "false";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00"; // If Automatic-Reboot is true

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Send email notification (requires mailx or similar and configured MTA)
// Unattended-Upgrade::Mail "your-email@example.com";
// Unattended-Upgrade::MailOnlyOnError "true";
EOF
    log "Created /etc/apt/apt.conf.d/50unattended-upgrades with basic settings."

    # Reconfigure to apply settings (optional, files should be picked up automatically)
    # sudo dpkg-reconfigure -plow unattended-upgrades

    info "Automatic updates configured. System will check for updates daily."
    info "Consider customizing /etc/apt/apt.conf.d/50unattended-upgrades for reboot behavior and package blacklists."
}

# Configure Fail2ban for SSH
configure_fail2ban() {
    log "Configuring Fail2ban for SSH protection..."

    # Ensure Fail2ban is installed
    if ! command -v fail2ban-client &> /dev/null; then
        error "Fail2ban command not found. Please ensure it's installed."
        return 1
    fi

    # Create jail.local for SSH (or use jail.d)
    # Using jail.d is generally preferred for modularity
    sudo mkdir -p /etc/fail2ban/jail.d/
    cat <<EOF | sudo tee /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = ssh    ; also supports custom ports e.g. 2222 or "ssh, 2222"
# filter = sshd  ; default filter, usually correct
logpath = %(sshd_log)s ; default log path, usually /var/log/auth.log
# backend = %(sshd_backend)s ; auto-detection, systemd is common
maxretry = 3
bantime = 1h   ; 1 hour. Use '1d' for a day, '1w' for a week. -1 for permanent (not recommended for SSH)
findtime = 10m ; 10 minutes window for retries

# Optional: Whitelist your IP addresses (space separated)
# ignoreip = 127.0.0.1/8 ::1 YOUR_STATIC_IP_1 YOUR_STATIC_IP_2
EOF
    log "Created /etc/fail2ban/jail.d/sshd.local for SSH protection."

    # Restart and enable Fail2ban service
    log "Restarting and enabling Fail2ban service..."
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban

    # Check status (optional)
    # sudo fail2ban-client status
    # sudo fail2ban-client status sshd

    info "Fail2ban configured for SSH."
}


# Create directory structure
create_directories() {
    log "Creating project directory structure..."

    # Create main directories
    mkdir -p ~/tmc-cloud/{docs,scripts,kubernetes,docker,configs,tools}
    mkdir -p ~/tmc-cloud/kubernetes/{namespaces,deployments,services,ingress,configmaps,secrets,persistent-volumes}
    mkdir -p ~/tmc-cloud/kubernetes/deployments/{github-runner,nextcloud,monitoring,databases}
    mkdir -p ~/tmc-cloud/docker/{compose,images}
    mkdir -p ~/tmc-cloud/docker/compose
    mkdir -p ~/tmc-cloud/docker/images/{base-ubuntu,github-runner,monitoring}
    mkdir -p ~/tmc-cloud/configs/{network,kubernetes,monitoring}
    mkdir -p ~/tmc-cloud/tools/{backup-scripts,monitoring-scripts,maintenance-scripts}
    mkdir -p ~/tmc-cloud/.github/{workflows,ISSUE_TEMPLATE}
    mkdir -p ~/tmc-cloud/{ansible,monitoring,backup,security,network,tests}
    mkdir -p ~/tmc-cloud/ansible/{playbooks,inventory,roles,group_vars}
    mkdir -p ~/tmc-cloud/monitoring/{prometheus,grafana,alertmanager,logs}
    mkdir -p ~/tmc-cloud/backup/{policies,scripts,restore}
    mkdir -p ~/tmc-cloud/security/{certificates,policies,compliance}
    mkdir -p ~/tmc-cloud/network/{firewall,vpn,dns}
    mkdir -p ~/tmc-cloud/tests/{integration,performance,security}

    # Create logs directory
    mkdir -p ~/tmc-cloud/logs

    info "Directory structure created"
}

# Install additional tools
install_additional_tools() {
    log "Installing additional tools..."

    # Install k9s (Kubernetes CLI management tool)
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
    wget -q https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz
    tar -xzf k9s_Linux_amd64.tar.gz
    sudo mv k9s /usr/local/bin/
    rm k9s_Linux_amd64.tar.gz

    # Install kubectl aliases and completion
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -F __start_kubectl k' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc

    # Install kubectx and kubens
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
    sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

    # Install act (run GitHub Actions locally)
    curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

    info "Additional tools installed"
}

# Generate SSH key if not exists
setup_ssh() {
    log "Setting up SSH configuration..."

    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        info "SSH key generated"
    else
        info "SSH key already exists"
    fi

    # Set proper permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
}

# Create configuration templates
create_config_templates() {
    log "Creating configuration templates..."

    # Network configuration template
    cat > ~/tmc-cloud/configs/network/network-config.yaml <<EOF
# Network Configuration Template
network:
  cluster_cidr: "192.168.1.0/24"
  pod_cidr: "10.244.0.0/16"
  service_cidr: "10.96.0.0/12"
  dns_domain: "cluster.local"

nodes:
  master:
    ip: "192.168.1.100"
    hostname: "k8s-master"
  worker1:
    ip: "192.168.1.101"
    hostname: "k8s-worker1"
  worker2:
    ip: "192.168.1.102"
    hostname: "k8s-worker2"
  storage:
    ip: "192.168.1.103"
    hostname: "k8s-storage"
EOF

    # Kubernetes cluster configuration template
    cat > ~/tmc-cloud/configs/kubernetes/cluster-config.yaml <<EOF
# Kubernetes Cluster Configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "192.168.1.100:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServer:
  advertiseAddress: "192.168.1.100"
etcd:
  local:
    dataDir: "/var/lib/etcd"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.1.100"
  bindPort: 6443
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

    # GitHub Actions workflow templates
    cat > ~/tmc-cloud/.github/workflows/ci.yml <<EOF
name: Continuous Integration

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: self-hosted
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: Run tests
      run: |
        echo "Running tests..."
        # Add your test commands here
    
    - name: Build Docker image
      run: |
        docker build -t test-image .
    
    - name: Security scan
      run: |
        echo "Running security scans..."
        # Add security scanning tools here
EOF

    cat > ~/tmc-cloud/.github/workflows/cd.yml <<EOF
name: Continuous Deployment

on:
  push:
    branches: [ main ]
  workflow_run:
    workflows: ["Continuous Integration"]
    types:
      - completed

jobs:
  deploy:
    runs-on: self-hosted
    if: \\${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
    - uses: actions/checkout@v4
    
    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: \\${{ github.actor }}
        password: \\${{ secrets.GITHUB_TOKEN }}
    
    - name: Build and push Docker image
      run: |
        docker build -t ghcr.io/\\${{ github.repository }}/app:latest .
        docker push ghcr.io/\\${{ github.repository }}/app:latest
    
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/app app=ghcr.io/\\${{ github.repository }}/app:latest
        kubectl rollout status deployment/app
EOF

    # GitHub runner configuration template
    cat > ~/tmc-cloud/configs/github-runner-config.yaml <<EOF
# GitHub Actions Runner Configuration
runner:
  name: "tmc-cloud-runner"
  labels: "self-hosted,linux,x64,kubernetes"
  work_directory: "/home/runner/work"
  
github:
  # These will be set during runner setup
  url: ""
  token: ""
  
resources:
  cpu_limit: "2"
  memory_limit: "4Gi"
  storage: "50Gi"
EOF

    info "Configuration templates created"
}

# Create GitHub Actions runner setup script
create_github_runner_script() {
    log "Creating GitHub Actions runner setup script..."

    cat > ~/tmc-cloud/scripts/setup-github-runner.sh <<'EOF'
#!/bin/bash

# GitHub Actions Self-hosted Runner Setup Script
# This script sets up a self-hosted GitHub Actions runner

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

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if GitHub CLI is installed
check_github_cli() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI is not installed. Please run setup-environment.sh first."
    fi
}

# Setup GitHub Actions runner
setup_runner() {
    log "Setting up GitHub Actions runner..."
    
    # Create runner directory
    mkdir -p ~/actions-runner
    cd ~/actions-runner
    
    # Download the latest runner package
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/v//')
    curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    
    # Extract the installer
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    
    info "Runner package downloaded and extracted"
    
    echo ""
    warn "MANUAL SETUP REQUIRED:"
    echo "1. Go to your GitHub repository settings"
    echo "2. Navigate to Actions > Runners"
    echo "3. Click 'New self-hosted runner'"
    echo "4. Copy the configuration command and run it in ~/actions-runner/"
    echo "5. Then run: sudo ./svc.sh install && sudo ./svc.sh start"
    echo ""
    info "Runner setup directory: ~/actions-runner"
}

# Main execution
main() {
    echo "===="
    echo "  GitHub Actions Runner Setup"
    echo "===="
    echo
    
    check_github_cli
    setup_runner
    
    log "GitHub Actions runner setup completed!"
    info "Please follow the manual setup instructions above."
}

main "$@"
EOF

    chmod +x ~/tmc-cloud/scripts/setup-github-runner.sh
    info "GitHub Actions runner setup script created"
}

# Final system check
final_check() {
    log "Performing final system check..."

    # Check Docker
    if ! docker --version &>/dev/null; then
        error "Docker installation failed"
    fi

    # Check Kubernetes tools
    if ! kubectl version --client &>/dev/null; then
        error "kubectl installation failed"
    fi

    if ! kubeadm version &>/dev/null; then
        error "kubeadm installation failed"
    fi

    # Check Helm
    if ! helm version &>/dev/null; then
        error "Helm installation failed"
    fi

    # Check GitHub CLI
    if ! gh --version &>/dev/null; then
        error "GitHub CLI installation failed"
    fi

    info "All tools installed successfully ✓"
}

# Main execution
main() {
    echo "===="
    echo "  On-Premises Cloud Infrastructure Setup"
    echo "  GitHub Actions CI/CD Integration"
    echo "===="
    echo

    check_root
    check_system

    log "Starting environment setup..."

    update_system
    install_essentials
    install_docker
    install_kubernetes
    install_helm
    install_github_cli
    configure_system
    setup_ufw_firewall # Replaced setup_firewall
    configure_automatic_updates # New
    configure_fail2ban # New
    create_directories
    install_additional_tools
    setup_ssh
    create_config_templates
    create_github_runner_script
    final_check

    echo
    echo "===="
    log "Environment setup completed successfully!"
    echo "===="
    echo
    info "SECURITY RECOMMENDATIONS:"
    info "  - For enhanced SSH security, consider manually editing /etc/ssh/sshd_config to:"
    info "    - Set 'PasswordAuthentication no' (use SSH keys only)"
    info "    - Set 'PermitRootLogin no'"
    info "    - Change the default SSH port (ensure UFW is updated if you do)"
    info "    Then restart the SSH service (e.g., sudo systemctl restart sshd)."
    info "  - Regularly review UFW rules (sudo ufw status verbose) and Fail2ban logs (/var/log/fail2ban.log)."
    info "  - Keep the system updated and monitor logs for security events."
    echo
    warn "IMPORTANT: Please reboot the system to ensure all changes take effect (especially kernel module loading, sysctl, and some package initializations)."
    warn "After reboot, you can proceed with cluster initialization."
    echo
    info "Next steps:"
    echo "  1. Reboot the system: sudo reboot"
    echo "  2. Configure network: ./scripts/configure-network.sh"
    echo "  3. Initialize cluster: ./scripts/setup-master.sh (on master node)"
    echo "  4. Join workers: ./scripts/setup-worker.sh (on worker nodes)"
    echo "  5. Setup GitHub runner: ./scripts/setup-github-runner.sh"
    echo
    info "Project directory: ~/tmc-cloud"
    info "Logs directory: ~/tmc-cloud/logs"
    info "GitHub workflows: ~/tmc-cloud/.github/workflows/"
    echo
    info "GitHub Actions Features:"
    echo "  • Self-hosted runners for your infrastructure"
    echo "  • GitHub Container Registry (ghcr.io) integration"
    echo "  • Automated CI/CD pipelines"
    echo "  • Security scanning and compliance checks"
    echo
}

# Run main function
main "$@"