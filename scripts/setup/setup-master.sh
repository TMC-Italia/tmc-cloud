#!/bin/bash

# CONFIGURATION FOR MASTER NODE:
# This script configures the current machine as the Kubernetes master node.
# Key configurations (like API server advertise IP, pod/service CIDRs) are set during 'kubeadm init'.
# The advertise IP '192.168.1.100' is currently hardcoded.
# TODO: Parameterize this IP or guide users to update it if their master IP differs.
# Ensure this IP is static and reachable by worker nodes.
# Review ~/tmc-cloud/configs/kubernetes/cluster-config.yaml for template values.

# Kubernetes Master Node Setup Script

source "$(dirname "$0")/common.sh"

# Initialize Kubernetes cluster
init_cluster() {
    log "Initializing Kubernetes cluster..."

    # Confirm UFW status (should be configured by setup-environment.sh)
    log "Checking UFW status..."
    if sudo ufw status | grep -q "Status: active"; then
        info "UFW is active. Ensure necessary master node ports are open (e.g., 6443, 2379-2380, 10250, CNI ports)."
        info "These should have been configured by 'setup-environment.sh'."
    else
        warn "UFW is not active or status could not be determined. This might lead to connectivity issues."
        warn "It is highly recommended to configure and enable UFW before proceeding."
        # Optionally, prompt to continue or exit
        # read -p "UFW is not active. Continue anyway? (y/N): " choice
        # if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        #    error "Aborting due to inactive UFW."
        # fi
    fi

    # Initialize cluster with kubeadm
    # --apiserver-advertise-address: The IP address the API Server will advertise on. Should be the master node's IP.
    # --pod-network-cidr: The CIDR range for pod IPs. Required for most CNI plugins like Calico.
    # --service-cidr: The CIDR range for service IPs.
    # --kubernetes-version: Specify the Kubernetes version.
    # Consider making APISERVER_ADVERTISE_ADDRESS and KUBERNETES_VERSION variables if they need to be dynamic.
    # For now, using values consistent with documentation/previous setup.
    info "Using master IP: 192.168.1.100 for apiserver-advertise-address. If your master node's IP is different, this script or the command needs to be updated."
    sudo kubeadm init \
        --apiserver-advertise-address=192.168.1.100 \
        --pod-network-cidr=10.244.0.0/16 \
        --service-cidr=10.96.0.0/12 \
        --kubernetes-version=v1.28.0 # Ensure this version matches tools installed by setup-environment.sh

    # Configure kubectl for regular user
    log "Configuring kubectl for the current user..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    info "Cluster initialized successfully"
}

# Install CNI plugin
install_cni() {
    log "Installing Calico CNI plugin..."

    # Install Calico
    # Ensure kubectl is usable before proceeding
    if ! kubectl version --client &> /dev/null; then
        error "kubectl command failed. Ensure cluster initialization and kubectl setup were successful."
        return 1
    fi
    log "Applying Calico operator manifest..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
    log "Applying Calico custom resources manifest..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/custom-resources.yaml

    # Wait for Calico pods to be ready (optional but recommended for sequencing)
    log "Waiting for Calico pods to be ready... This might take a few minutes."
    # This is a basic check, more robust checks might be needed for production.
    # Adjust namespace and labels as per your Calico installation details.
    # Timeout after 5 minutes.
    kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=300s || warn "Calico nodes may not be fully ready."
    kubectl wait --for=condition=Ready pods -l k8s-app=calico-kube-controllers -n calico-system --timeout=300s || warn "Calico kube-controllers may not be fully ready."

    info "Calico CNI installation initiated. Monitor pod status in 'calico-system' namespace."
}

# Apply default network policies
apply_default_network_policies() {
    log "Applying default network policies..."

    log "Applying 'default-deny-all' NetworkPolicy to 'default' namespace..."
    kubectl apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {} # Selects all pods in the namespace
  policyTypes:
  - INGRESS
  - EGRESS
EOF
    info "'default-deny-all' policy applied to 'default' namespace."

    log "Applying 'allow-dns-access' NetworkPolicy to 'default' namespace..."
    # This policy allows pods in 'default' to query kube-dns in 'kube-system'.
    # Ensure the label 'kubernetes.io/metadata.name: kube-system' exists on the kube-system namespace.
    # This can be checked with: kubectl get namespace kube-system --show-labels
    # If not present, adjust namespaceSelector or label the namespace:
    # kubectl label namespace kube-system kubernetes.io/metadata.name=kube-system
    kubectl apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-dns-access
  namespace: default
spec:
  podSelector: {} # Affects all pods in 'default'
  policyTypes:
  - EGRESS
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          # This label should ideally be present on kube-system namespace by default in recent k8s versions.
          # If not, 'kubernetes.io/metadata.name: kube-system' is a common one.
          # Or use a more direct selector if Calico/K8s adds specific labels to kube-system.
          # For maximum compatibility, one might need to verify this label or use a known one like 'name: kube-system' if that's standard.
          # For now, relying on a common convention for the kube-system namespace identifier.
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns # Standard label for kube-dns pods
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
    info "'allow-dns-access' policy applied to 'default' namespace."

    log "Applying 'allow-internet-egress' NetworkPolicy to 'default' namespace..."
    # This is a broad rule. For tighter security, restrict this further.
    # The 'except' clauses are important to ensure that traffic to internal/cluster CIDRs
    # is not inadvertently blocked if it doesn't match a more specific allow rule.
    kubectl apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-internet-egress
  namespace: default
spec:
  podSelector: {} # Affects all pods in 'default'
  policyTypes:
  - EGRESS
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        # Common private IP ranges. Adjust based on your network.
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
        # Add your specific Pod CIDR and Service CIDR if they are not covered
        # For example, if pod CIDR is 10.244.0.0/16 and service CIDR is 10.96.0.0/12
        # these are already covered by 10.0.0.0/8.
EOF
    info "'allow-internet-egress' policy applied to 'default' namespace."

    warn "Default network policies (deny-all, allow-dns, allow-internet-egress) have been applied to the 'default' namespace."
    warn "You will need to create specific NetworkPolicies to allow desired traffic between your application pods."
    info "Consider applying similar restrictive policies to 'kube-system' and other namespaces with caution, ensuring critical cluster communication is not blocked."
}


# Install ingress controller
install_ingress() {
    log "Installing NGINX Ingress Controller..."
    info "NGINX Ingress Controller is being installed. For production environments, consider deploying and managing the ingress controller as a separate, dedicated step with customized configurations and security hardening (e.g., TLS certificates, specific annotations, resource limits)."

    # Install NGINX Ingress Controller for bare-metal
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml

    info "NGINX Ingress Controller installation manifest applied."
}

# Main execution
main() {
    echo "===="
    echo "  Kubernetes Master Node Setup"
    echo "===="
    echo

    init_cluster
    install_cni
    apply_default_network_policies # New step
    install_ingress

    log "Master node setup completed!"

    echo
    info "To join worker nodes to the cluster, run the following command on each worker."
    warn "This join token is SENSITIVE and should be handled securely. It is valid for 24 hours by default."
    echo
    sudo kubeadm token create --print-join-command
    echo
}

main "$@"