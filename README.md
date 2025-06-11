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
# Adjust paths according to the new structure in scripts/
chmod +x scripts/setup/*.sh scripts/deployment/*.sh scripts/maintenance/*.sh scripts/utils/*.sh

# Run initial setup
./scripts/setup/setup-environment.sh # (Prepares each node, now includes UFW, Fail2ban, auto-updates, and hostname guidance)
```

### 2. Network Configuration

```bash
# Configure network on each node
./scripts/setup/configure-network.sh
```

### 3. Kubernetes Cluster Setup

```bash
# On master node
./scripts/setup/setup-master.sh # (Initializes K8s master, now applies default network policies)

# On worker nodes
./scripts/setup/setup-worker.sh # (Joins worker to cluster, now with enhanced security guidance)
```

## Multi-Node Deployment Notes

Deploying this system across multiple laptops (nodes) requires careful attention to a few key areas:

-   **Unique Hostnames:** Crucial for a multi-node Kubernetes cluster, each laptop/node *must* have a unique hostname. The `scripts/setup/setup-environment.sh` script will warn you if a generic hostname (like "ubuntu" or "localhost") is detected and provide instructions to change it (e.g., using `sudo hostnamectl set-hostname my-master`). Remember to update `/etc/hosts` accordingly and reboot if you change the hostname.

-   **Script Execution Order:**
    1.  Run `scripts/setup/setup-environment.sh` on *all* laptops that will be part of the cluster. This script prepares the common base environment.
    2.  Run `scripts/setup/setup-master.sh` on the *one* laptop designated as the Kubernetes master node.
    3.  Run `scripts/setup/setup-worker.sh` on *each* of the laptops designated as worker nodes. You will need the join command output by `setup-master.sh`.

-   **Configuration & IP Addresses:** The setup scripts, particularly `setup-master.sh`, contain some hardcoded IP addresses (e.g., `192.168.1.100` for the master node's API server). If your network configuration or chosen master IP differs, you'll need to adjust these values within the scripts themselves. Look for comments within the scripts for guidance on where these are set. For more advanced setups, consider parameterizing these values using environment variables or a separate configuration file. The `network-config.yaml` template created by `setup-environment.sh` should also be reviewed and aligned with your network plan.

### 4. Deploy Core Services

```bash
# Deploy monitoring stack
./scripts/deployment/deploy-monitoring.sh

# Setup backup system
./scripts/setup/setup-backup.sh

# Setup GitHub Actions runner
./scripts/setup-github-runner.sh # Note: This script was not part of the recent reorganization tasks. Its location and content should be verified.
```

### 5. Configure Remote Access

```bash
# Configure Tailscale for secure VPN access
./scripts/setup/setup-tailscale.sh

# Configure Cloudflare for public access
./scripts/setup/setup-cloudflare.sh yourdomain.com

# Or run without domain (manual DNS setup)
./scripts/setup/setup-cloudflare.sh
```

### 6. Maintenance & Health Checks

```bash
# Run system health check
./scripts/maintenance/system-health-check.sh
```

## Repository Structure

The repository is organized into several key directories to maintain clarity and separation of concerns:

-   **`configs/`**: Contains configuration files.
    -   `configs/environments/`: Holds environment-specific configurations like `dev.example.yml` and `prod.example.yml`.
-   **`docker/`**: Contains Docker-related files.
    -   `docker/images/`: Houses Dockerfiles and related scripts (e.g., `entrypoint.sh`) for building container images, organized by image name.
    -   `docker-compose.yml`: The main Docker Compose file for local development and service orchestration.
-   **`kubernetes/`**: Contains Kubernetes manifest files.
    -   `kubernetes/namespaces/`: YAML files defining Kubernetes namespaces.
    -   `kubernetes/deployments/`: YAML files for application and service deployments. This includes actual deployment files like `github-runner-deployment.yaml` and `nextcloud-deployment.yaml`.
    -   `kubernetes/configmaps/`: YAML files for ConfigMaps.
    -   `kubernetes/services/`: YAML files defining Kubernetes services (Note: Directory to be populated).
    -   `kubernetes/ingress/`: YAML files for Ingress controllers and rules (Note: Directory to be populated).
    -   `kubernetes/storage/`: YAML files related to persistent storage, like PersistentVolumeClaims or StorageClass definitions, and placeholder files like `.gitkeep`.
    -   `kubernetes/helm-charts/`: Contains Helm charts for deploying applications (currently holds a `.gitkeep`).
-   **`scripts/`**: Contains shell scripts for various automation tasks.
    -   `scripts/setup/`: Scripts related to initial setup and configuration of the environment and nodes (e.g., `setup-environment.sh`, `configure-network.sh`, `setup-master.sh`, `setup-backup.sh`).
    -   `scripts/deployment/`: Scripts for deploying applications or services (e.g., `deploy-monitoring.sh`).
    -   `scripts/maintenance/`: Scripts for system maintenance tasks (e.g., `system-health-check.sh`).
    -   `scripts/utils/`: Utility scripts that might be used by other scripts (e.g., `common.sh`).

## Example Files

To help users get started and understand the configuration and scripting patterns, the following example files have been provided:

-   **`configs/environments/dev.example.yml`**: An example configuration file tailored for a development environment. It includes settings like debug mode, local database connections, and mock service endpoints.
-   **`configs/environments/prod.example.yml`**: An example configuration file for a production environment. It emphasizes security, robustness, and the use of production-level services and secrets management.
-   **`scripts/deployment/deploy-app.example.sh`**: An example shell script outlining the steps for deploying an application. It covers typical deployment phases like pre-deployment checks, image updates, rollout status checks, and post-deployment tasks.
-   **`scripts/setup/setup-backup.example.sh`**: An example shell script demonstrating how to set up and perform backups. It includes placeholders for database backups, application data backups, transfer to remote storage, and cleanup.

These example files should be copied and modified according to your specific requirements. For instance, rename `dev.example.yml` to `dev.yml` and populate it with your actual development settings.

## Pre-commit Checks

This repository uses pre-commit hooks to ensure code quality and consistency before commits are made. This helps catch common issues early.

### Setup

To use the pre-commit hooks, you need to have `pre-commit` installed.

1.  **Install pre-commit**:
    If you don't have it installed, you can install it using pip:
    ```bash
    pip install pre-commit
    ```

2.  **Install the git hooks**:
    Navigate to the root of the repository and run:
    ```bash
    pre-commit install
    ```
    This will set up the pre-commit script to run automatically before each commit.

### Usage

Once installed, pre-commit will run automatically when you `git commit`. It will check the staged files against the configured hooks (see `.pre-commit-config.yaml`).

-   If any checks fail, the commit will be aborted. You'll see an error message indicating which hook failed and why.
-   Fix the issues reported by the hooks (some hooks like `trailing-whitespace` or `end-of-file-fixer` might fix them automatically).
-   After fixing, `git add` the modified files and try committing again.

### Available Hooks

The following hooks are configured:

-   **YAML Linter (`yamllint`)**: Checks YAML files for syntax errors and style issues. Configuration can be customized in `.yamllint.yaml`.
-   **Shell Script Linter (`shellcheck`)**: Performs static analysis on shell scripts to find potential bugs and improve style.
-   **Trailing Whitespace**: Trims trailing whitespace from files.
-   **End of File Fixer**: Ensures files end with a single newline.
-   **Check YAML/JSON**: Basic syntax checks for YAML and JSON files.
-   **Check Added Large Files**: Prevents accidental commits of large files.
-   **Mixed Line Ending**: Ensures consistent line endings (LF).

You can manually run all pre-commit hooks on all files at any time with:
```bash
pre-commit run --all-files
```

## Network Configuration

### IP Address Scheme

- **Master Node**: 192.168.1.100 - READY
- **Worker Node 1**: 192.168.1.101 - READY
- **Worker Node 2**: 192.168.1.102
- **Storage Node**: 192.168.1.103 - READY

- **Gateway**: 192.168.1.1

- **Subnet**: 192.168.1.0/24

### Firewall Configuration

Firewall rules are managed by **UFW (Uncomplicated Firewall)**, which is configured by the `scripts/setup/setup-environment.sh` script on each node. UFW is set with a default policy of denying incoming traffic and allowing outgoing. Specific rules are added to allow essential services for Kubernetes, SSH, and remote access tools as detailed in their respective setup scripts and the "Enhanced Security Measures" section. For specific port requirements for Tailscale and Cloudflare, see the "Remote Access" section below.

## Remote Access

Secure remote access to your cluster and services is crucial. This project provides setup scripts for Tailscale (for private VPN access) and Cloudflare Tunnels (for public exposure of services).

### Tailscale VPN Setup (`scripts/setup/setup-tailscale.sh`)

- **Purpose**: Provides secure, private network access to your nodes for administration and internal service communication without exposing them directly to the internet.
- **Features**: Zero-config mesh VPN, end-to-end encryption, identity-based access control.
- **Use Case**: Administrator access to Kubernetes nodes, direct access to internal services not meant for public exposure.

**Key Enhancements & Setup Notes:**

-   **Interactive Setup:** The `scripts/setup/setup-tailscale.sh` script is now more interactive:
    -   **Authentication:** You'll be prompted to choose between interactive browser login or using a Tailscale auth key. Auth keys are recommended for headless servers or automated setups; remember to handle them securely (e.g., as ephemeral or pre-authorized keys).
    -   **Advertised Subnets:** You can specify comma-separated subnets (e.g., `192.168.1.0/24`) that this node should advertise to your Tailscale network. Leave this empty if the node should not act as a subnet router.
    -   **Device Hostname:** You can set a custom Tailscale device hostname, which defaults to `your-system-hostname-k8s`.
-   **Firewall Integration (UFW):** Firewall rules for Tailscale are now managed using `ufw`, consistent with the base environment setup. The script allows traffic on the `tailscale0` interface and UDP port 41641 (for NAT traversal), ensuring Tailscale can operate effectively.
-   **IP Forwarding:** If you choose to advertise subnets, IP forwarding will be enabled on the node. The script includes warnings about this and emphasizes the importance of securing access to these advertised routes using Tailscale ACLs.
-   **Idempotency:** The script has been improved for better idempotency, particularly for `sysctl` settings related to IP forwarding.
-   **Critical Security Note - ACLs:** After setting up Tailscale and especially if advertising routes, it is **CRITICAL** to configure Access Control Lists (ACLs) in your Tailscale admin console (`https://login.tailscale.com/admin/acls`). ACLs define which devices can connect to each other and which users/tags can access advertised subnets. **Do not skip this step** to maintain a secure private network.

### Cloudflare Tunnel Setup (`scripts/setup/setup-cloudflare.sh`)

- **Purpose**: Securely exposes your self-hosted services to the internet without needing to open firewall ports or have a static public IP.
- **Features**: TLS encryption, DDoS protection, Web Application Firewall (WAF) capabilities (via Cloudflare dashboard), OAuth integration for access control.
- **Use Case**: Public access to web applications, APIs, and services like Grafana or GitLab, often integrated with Cloudflare Access for authentication.

**Key Enhancements & Setup Notes:**

-   **Interactive Tunnel Name:** The `scripts/setup/setup-cloudflare.sh` script now prompts for a **Tunnel Name** (defaults to `on-premises-k8s`), allowing for more flexible naming.
-   **IMPORTANT Security Update - TLS Verification:**
    -   The script **no longer sets `noTLSVerify: true` by default** in the Cloudflare Tunnel configuration file (`/etc/cloudflared/config.yml`).
    -   This is a critical security improvement: `cloudflared` will now **VERIFY TLS certificates** for your origin HTTPS services.
    -   **Action Required:**
        -   If your internal services are exposed via HTTPS, they **must present valid TLS certificates** (e.g., from an internal Certificate Authority or Let's Encrypt).
        -   If your origin service is HTTP (e.g., `http://localhost:8000`), `cloudflared` will handle TLS termination at the Cloudflare edge, and no origin certificate is needed for that specific service.
        -   If you absolutely must use self-signed certificates for an internal HTTPS service and fully understand the security risks (e.g., disabling protection against man-in-the-middle attacks between `cloudflared` and your origin), you can manually add `originRequest: { noTLSVerify: true }` to that *specific service's* ingress rule in `/etc/cloudflared/config.yml`. This is **strongly discouraged for production environments.**
-   **Manual Ingress Configuration:**
    -   The generated `/etc/cloudflared/config.yml` is now a **minimal template**. You **MUST edit this file** to add your specific ingress rules, defining which local services to expose under which public hostnames.
    -   The script provides comments and an example within the generated `config.yml` to guide you. The `~/on-premises-cloud/tools/cloudflare/update-config.sh` script can be used to safely edit this file.
-   **Manual DNS Routing:**
    -   Consistent with manual ingress configuration, DNS routing is **no longer automated** by the script.
    -   After configuring your hostnames in `config.yml`, you must manually create DNS records for each using the command: `cloudflared tunnel route dns <YOUR_TUNNEL_NAME> <your.hostname.com>`. The setup script will remind you of this.
-   **Metrics Endpoint:** The `cloudflared` metrics endpoint is now configured on `localhost:8081` (previously `0.0.0.0:8080`) for improved security, limiting direct exposure.
-   **Authentication & OAuth:**
    -   Authentication to Cloudflare (to link `cloudflared` to your account) still typically uses `cloudflared tunnel login` (browser-based). For headless server setups, the `cert.pem` file can be pre-placed in `~/.cloudflared/` to skip this interactive step.
    -   Remember to manually configure **OAuth (or other Access policies)** for your exposed applications in the Cloudflare Zero Trust dashboard to secure them. The script provides guidance on where to do this.

## Security Considerations

- **Network Isolation**: Private network with firewall protection
- **Encryption**: TLS/SSL for all communications
- **Access Control**: OAuth integration via Cloudflare
- **Backup Encryption**: Encrypted offsite backups
- **Certificate Management**: cert-manager for automatic SSL certificates
- **GitHub Secrets**: Secure storage of CI/CD secrets and tokens

### Enhanced Security Measures

The setup scripts incorporate several security best practices by default:

-   **Firewall (UFW):** The `setup-environment.sh` script configures UFW (Uncomplicated Firewall) on each node. It establishes a default policy of denying all incoming traffic and allowing all outgoing traffic. Specific rules are added to allow essential services, including:
    -   SSH (port 22/tcp)
    -   Kubernetes components: API server (6443/tcp), etcd (2379-2380/tcp), Kubelet (10250/tcp), NodePort services (30000-32767/tcp).
    -   CNI communication (Calico): BGP (179/tcp), IP-in-IP (protocol `ipip`).
    -   HTTP/S traffic (ports 80/tcp, 443/tcp).

-   **Intrusion Prevention (Fail2ban):** `Fail2ban` is installed and configured by `setup-environment.sh`. It actively monitors SSH logs and temporarily bans IP addresses that exhibit malicious behavior, such as excessive incorrect password attempts, thereby mitigating brute-force attack risks.

-   **Automatic Security Updates:** The `unattended-upgrades` package is configured via `setup-environment.sh` to automatically download and install security patches daily. This helps protect the system against known vulnerabilities with minimal manual intervention. To prevent unintended disruptions to the Kubernetes cluster, packages like `kubeadm`, `kubelet`, and `kubectl` are blacklisted from automatic upgrades.

-   **SSH Hardening Guidance:** While the scripts set up basic SSH access and Fail2ban, users are strongly encouraged to manually enhance SSH security further:
    *   **Disable password authentication:** Enforce key-based authentication for stronger protection against password guessing.
    *   **Disable direct root login:** Prevent root users from logging in directly via SSH.
    *   These changes can be made by editing `/etc/ssh/sshd_config` and restarting the `sshd` service (e.g., `sudo systemctl restart sshd`). The `setup-environment.sh` script provides a reminder for these manual steps.

-   **Kubernetes Network Policies:** The `setup-master.sh` script now applies default network policies to the `default` namespace using Calico CNI. These policies institute a "default deny" for all ingress and egress traffic for pods in that namespace. Specific rules are then added to:
    *   Allow DNS resolution (to `kube-dns` pods in `kube-system`).
    *   Allow basic internet egress from pods.
    *   **Important:** Users *must* create explicit `NetworkPolicy` resources to allow any other required communication between their application pods or to/from external services. Guidance is also provided to consider similar policies for other namespaces like `kube-system`, applied cautiously.

-   **Secure Token Handling:** The `kubeadm join` token, generated on the master node and used to add worker nodes, is critical for cluster security. The `setup-master.sh` and `setup-worker.sh` scripts now include explicit warnings to handle this token securely during its transfer and use, as it grants significant privileges.

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