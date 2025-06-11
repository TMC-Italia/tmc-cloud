#!/bin/bash

# Monitoring Stack Deployment Script

source "$(dirname "$0")/common.sh"

# Create monitoring namespace
create_namespace() {
    log "Creating monitoring namespace..."
  
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  
    info "Monitoring namespace created"
}

# Install Prometheus
install_prometheus() {
    log "Installing Prometheus..."
  
    # Add Prometheus Helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
  
    # Install Prometheus
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set grafana.adminPassword=admin123 \
        --set prometheus.prometheusSpec.retention=30d
  
    info "Prometheus installed"
}

# Install Loki
install_loki() {
    log "Installing Loki..."
  
    # Add Grafana Helm repository
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
  
    # Install Loki
    helm install loki grafana/loki-stack \
        --namespace monitoring \
        --set grafana.enabled=false \
        --set prometheus.enabled=false
  
    info "Loki installed"
}

# Main execution
main() {
    echo "===="
    echo "  Monitoring Stack Deployment"
    echo "===="
    echo
  
    create_namespace
    install_prometheus
    install_loki
  
    log "Monitoring stack deployed successfully!"
  
    echo
    info "Access Grafana:"
    echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo
}

main "$@"