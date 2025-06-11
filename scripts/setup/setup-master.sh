#!/bin/bash

# Kubernetes Master Node Setup Script

source "$(dirname "$0")/common.sh"

# Initialize Kubernetes cluster
init_cluster() {
    log "Initializing Kubernetes cluster..."
  
    # Initialize cluster with kubeadm
    sudo kubeadm init \
        --apiserver-advertise-address=192.168.1.100 \
        --pod-network-cidr=10.244.0.0/16 \
        --service-cidr=10.96.0.0/12 \
        --kubernetes-version=v1.28.0
  
    # Configure kubectl for regular user
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
  
    info "Cluster initialized successfully"
}

# Install CNI plugin
install_cni() {
    log "Installing Calico CNI plugin..."
  
    # Install Calico
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/custom-resources.yaml
  
    info "Calico CNI installed"
}

# Install ingress controller
install_ingress() {
    log "Installing NGINX Ingress Controller..."
  
    # Install NGINX Ingress Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml
  
    info "NGINX Ingress Controller installed"
}

# Main execution
main() {
    echo "===="
    echo "  Kubernetes Master Node Setup"
    echo "===="
    echo
  
    init_cluster
    install_cni
    install_ingress
  
    log "Master node setup completed!"
  
    echo
    info "To join worker nodes to the cluster, run the following command on each worker:"
    echo
    sudo kubeadm token create --print-join-command
    echo
}

main "$@"