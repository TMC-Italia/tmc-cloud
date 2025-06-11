#!/bin/bash

# On-Premises Cloud Infrastructure - Environment Setup Script
# This script prepares the system for Kubernetes cluster deployment
# Author: Based on project documentation by  Silvio Mario Pastori, Flavio Renzi, Marco Selva, Carmine Scacco
# Date: 2025-06-11
# Version: 1.0

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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
    sudo apt install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        net-tools \
        nfs-common \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        jq \
        unzip \
        tree \
        rsync \
        iptables-persistent
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

# Configure system settings
configure_system() {
    log "Configuring system settings..."

    # Disable swap (required for Kubernetes)
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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

# Setup firewall rules
setup_firewall() {
    log "Configuring firewall rules..."

    # Reset iptables rules
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t nat -X
    sudo iptables -t mangle -F
    sudo iptables -t mangle -X

    # Allow loopback
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow SSH
    sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # Kubernetes ports
    sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT      # API Server
    sudo iptables -A INPUT -p tcp --dport 2379:2380 -j ACCEPT # etcd
    sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT     # Kubelet
    sudo iptables -A INPUT -p tcp --dport 10251 -j ACCEPT     # kube-scheduler
    sudo iptables -A INPUT -p tcp --dport 10252 -j ACCEPT     # kube-controller-manager
    sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT # NodePort Services

    # HTTP/HTTPS
    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # Allow internal cluster communication
    sudo iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
    sudo iptables -A INPUT -s 10.244.0.0/16 -j ACCEPT  # Pod network

    # Default policies
    sudo iptables -P INPUT DROP
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -P OUTPUT ACCEPT

    # Save rules
    sudo netfilter-persistent save

    info "Firewall rules configured"
}

# Create directory structure
create_directories() {
    log "Creating project directory structure..."

    # Create main directories
    mkdir -p ~/tmc-cloud/{docs,scripts,kubernetes,docker,configs,tools}
    mkdir -p ~/tmc-cloud/kubernetes/{manifests,helm-charts}
    mkdir -p ~/tmc-cloud/kubernetes/manifests/{gitlab,monitoring,storage,ingress}
    mkdir -p ~/tmc-cloud/docker/{gitlab,monitoring,backup}
    mkdir -p ~/tmc-cloud/configs/{network,kubernetes,gitlab,monitoring}
    mkdir -p ~/tmc-cloud/tools/{backup-scripts,monitoring-scripts,maintenance-scripts}

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

    info "Configuration templates created"
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

    info "All tools installed successfully ✓"
}

# Main execution
main() {
    echo "=================================================="
    echo "  On-Premises Cloud Infrastructure Setup"
    echo "=================================================="
    echo

    check_root
    check_system

    log "Starting environment setup..."

    update_system
    install_essentials
    install_docker
    install_kubernetes
    install_helm
    configure_system
    setup_firewall
    create_directories
    install_additional_tools
    setup_ssh
    create_config_templates
    final_check

    echo
    echo "=================================================="
    log "Environment setup completed successfully!"
    echo "=================================================="
    echo
    warn "IMPORTANT: Please reboot the system to ensure all changes take effect."
    warn "After reboot, you can proceed with cluster initialization."
    echo
    info "Next steps:"
    echo "  1. Reboot the system: sudo reboot"
    echo "  2. Configure network: ./scripts/configure-network.sh"
    echo "  3. Initialize cluster: ./scripts/setup-master.sh (on master node)"
    echo "  4. Join workers: ./scripts/setup-worker.sh (on worker nodes)"
    echo
    info "Project directory: ~/tmc-cloud"
    info "Logs directory: ~/tmc-cloud/logs"
    echo
}

# Run main function
main "$@"
