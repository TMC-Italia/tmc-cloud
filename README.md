# TMC-Cloud

TMC Cloud On-Premises: Repurposing old laptops to power a state-of-the-art cloud hosting and computing solution.

## Overview

TMC Cloud is a self-hosted cloud platform designed to empower users to run their own cloud services using repurposed hardware. It provides a user-friendly interface for managing containers and other cloud resources, making cloud computing accessible without reliance on third-party providers. This project is aimed at BMs and Employeneurs looking to leverage a private cloud infrastructure.

- **Timeline**: Q2 2025 completion target

## Project Overview

This project transforms legacy company PCs into a powerful on-premises private cloud infrastructure using Kubernetes and GitHub Actions. The solution provides a scalable, fault-tolerant environment that supports essential applications and continuous integration processes while optimizing cost-efficiency and sustainability.

### Key Features

- **Kubernetes Orchestration**: Container orchestration with high availability
- **GitHub Actions CI/CD**: Complete DevOps pipeline with GitHub-hosted runners
- **Remote Access**: Secure remote access via Tailscale VPN and Cloudflare Tunnels
- **Persistent Storage**: Distributed storage with Ceph/NFS/MinIO
- **Monitoring**: Comprehensive monitoring with Prometheus, Grafana, and Loki
- **Backup & Recovery**: Automated backup with Velero
- **Container Registry**: GitHub Container Registry (ghcr.io) integration

## Architecture

``` plaintext
End Users  
    ↓  
Private Network Firewall  
    ↓  
Kubernetes Ingress Gateway  
    ↓  
┌─────────────────┬─────────────────┬─────────────────┐  
│ Application     │ GitHub Actions  │ Self-hosted     │  
│ Pods            │ (CI/CD)         │ Runners         │  
└─────────────────┴─────────────────┴─────────────────┘  
    ↓  
Persistent Storage (Encrypted, Distributed)  
    ↓  
┌─────────────────┬─────────────────┐  
│ Velero Backup   │ Monitoring      │  
│ Pods            │ (Prometheus,    │  
│                 │ Grafana, Loki)  │  
└─────────────────┴─────────────────┘  
    ↓  
Secure Offsite Backup  
```

## Hardware Requirements

### Minimum Configuration (4 PCs)

|Role|Quantity|CPU|RAM|Storage|Purpose|
|---|---|---|---|---|---|
|Master Node|1|4 cores|8 GB|100 GB SSD|Kubernetes Control Plane|
|Worker Node 1|1|2 cores|4-8 GB|100 GB SSD|Application Pods|
|Worker Node 2|1|4 cores|8 GB|200 GB SSD|GitHub Actions Runner + CI/CD|
|Storage/Backup|1|2 cores|4 GB|200 GB HDD/SSD|NFS, MinIO, Backup|

## Quick Start

### Prerequisites

- 4 PCs with Ubuntu Server installed
- Network connectivity between all nodes
- Domain name for external access
- Basic Linux administration knowledge
- GitHub repository with Actions enabled

### 1. Initial Setup

```bash
# Clone the repository
git clone https://github.com/TMC-Italia/tmc-cloud
cd tmc-cloud

# Make scripts executable
chmod +x scripts/*.sh scripts/maintenance/*.sh

# Run initial setup
./scripts/setup-environment.sh
```

### 2. Network Configuration

```bash
# Configure network on each node
./scripts/configure-network.sh
```

### 3. Kubernetes Cluster Setup

```bash
# On master node
./scripts/setup-master.sh

# On worker nodes
./scripts/setup-worker.sh
```

### 4. Deploy Core Services

```bash
# Deploy monitoring stack
./scripts/deploy-monitoring.sh

# Setup backup system
./scripts/setup-backup.sh

# Setup GitHub Actions runner
./scripts/setup-github-runner.sh
```

### 5. Configure Remote Access

```bash
# Configure Tailscale for secure VPN access
./scripts/setup-tailscale.sh

# Configure Cloudflare for public access
./scripts/setup-cloudflare.sh yourdomain.com

# Or run without domain (manual DNS setup)
./scripts/setup-cloudflare.sh
```

### 6. Maintenance & Health Checks

```bash
# Run system health check
./scripts/maintenance/system-health-check.sh
```

## Network Configuration

### IP Address Scheme

- **Master Node**: 192.168.1.100 - READY
- **Worker Node 1**: 192.168.1.101 - READY
- **Worker Node 2**: 192.168.1.102
- **Storage Node**: 192.168.1.103 - READY

- **Gateway**: 192.168.1.1

- **Subnet**: 192.168.1.0/24

### Firewall Rules

- Port 6443: Kubernetes API Server
- Port 2379-2380: etcd
- Port 10250: Kubelet
- Port 30000-32767: NodePort Services
- Port 80/443: HTTP/HTTPS traffic

## Remote Access

### Tailscale VPN

- **Purpose**: Secure administrative access
- **Features**: Mesh VPN, easy setup, reliable connectivity
- **Use Case**: Administrator access to all nodes

### Cloudflare Tunnel

- **Purpose**: Public service exposure
- **Features**: OAuth integration, subdomain routing
- **Use Case**: External access to applications and monitoring

## Security Considerations

- **Network Isolation**: Private network with firewall protection
- **Encryption**: TLS/SSL for all communications
- **Access Control**: OAuth integration via Cloudflare
- **Backup Encryption**: Encrypted offsite backups
- **Certificate Management**: cert-manager for automatic SSL certificates
- **GitHub Secrets**: Secure storage of CI/CD secrets and tokens

## Services & Components

### Core Kubernetes Components

- **Control Plane**: API Server, Scheduler, Controller Manager
- **Network Plugin**: Calico (Pod network CIDR: 192.168.0.0/16)
- **Ingress Controller**: NGINX Ingress Controller
- **Storage**: NFS, MinIO, Ceph (optional)

### GitHub Actions Integration

- **Self-hosted Runners**: Dedicated runners on your infrastructure
- **Container Registry**: GitHub Container Registry (ghcr.io)
- **Secrets Management**: GitHub Secrets for secure CI/CD
- **Workflow Automation**: Automated testing, building, and deployment

### Monitoring Stack

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation and analysis
- **AlertManager**: Alert routing and management

### Backup & Recovery

- **Velero**: Kubernetes backup and disaster recovery
- **MinIO**: S3-compatible object storage
- **Automated Backups**: Daily snapshots of critical data

## Monitoring & Observability

### Key Metrics

- **Cluster Health**: Node status, pod health, resource usage
- **Application Performance**: Response times, error rates
- **Infrastructure**: CPU, memory, disk, network utilization
- **CI/CD Metrics**: Pipeline success rates, deployment frequency

### Alerting

- **Critical Alerts**: Node failures, service outages
- **Warning Alerts**: High resource usage, backup failures
- **Info Alerts**: Successful deployments, maintenance windows

## Backup Strategy

### What's Backed Up

- **Kubernetes Manifests**: All cluster configurations
- **Persistent Volumes**: Application data and databases
- **Application Data**: User data and configurations
- **System Configurations**: Network, security settings

### Backup Schedule

- **Daily**: Incremental backups of critical data
- **Weekly**: Full system snapshots
- **Monthly**: Long-term archival backups

## Maintenance & Updates

### Regular Tasks

- **Security Updates**: Monthly OS and package updates
- **Kubernetes Updates**: Quarterly cluster upgrades
- **Backup Verification**: Weekly restore tests
- **Performance Monitoring**: Continuous optimization

### Troubleshooting

- **Log Analysis**: Centralized logging with Loki
- **Performance Issues**: Grafana dashboards and alerts
- **Network Problems**: Connectivity and routing diagnostics
- **Storage Issues**: Persistent volume monitoring

## Development Workflow

### GitHub Actions CI/CD Pipeline

1. **Code Commit**: Developer pushes code to GitHub
2. **Build Stage**: GitHub Actions builds application
3. **Test Stage**: Automated testing and quality checks
4. **Security Scan**: Container and dependency scanning
5. **Deploy Stage**: Deployment to Kubernetes cluster
6. **Monitor**: Continuous monitoring and alerting

### GitHub Actions Features

- **Self-hosted Runners**: Run CI/CD on your own infrastructure
- **Matrix Builds**: Test across multiple environments
- **Secrets Management**: Secure handling of credentials
- **Artifact Storage**: Build artifacts and test results
- **Integration**: Seamless integration with GitHub ecosystem

## License

This project is proprietary to the company and intended for internal use only.

## Contact

- **Project Lead**: Silvio Mario Pastori
- **Technical Leads**: Flavio Renzi, Marco Selva, Carmine Scacco

---

_Last updated: June 2025_