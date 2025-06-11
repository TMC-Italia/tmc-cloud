# Makefile for TMC-Cloud Operations

.PHONY: help system-health \
        k8s-cluster-info k8s-nodes k8s-all-pods k8s-events k8s-services k8s-logs k8s-shell k8s-port-forward k8s-top-nodes k8s-top-pods k8s-ns-pods k8s-ns-services \
        docker-info docker-stats docker-logs docker-shell \
        tailscale-status cloudflare-status \
        network-interfaces network-ports network-ping network-dns-lookup

# Variables (can be overridden on the command line, e.g., make k8s-logs POD=my-pod NS=my-ns)
NS ?= default
POD ?=
CONTAINER ?=
SVC ?=
LOCAL_PORT ?= 8080
REMOTE_PORT ?= 80
TARGET_HOST ?= google.com
CLOUDFLARE_TUNNEL_NAME ?= on-premises-k8s # Default, can be overridden. Update if your tunnel name differs.

# Default target
help:
	@echo "TMC-Cloud Makefile - Common Operations"
	@echo ""
	@echo "Usage: make <target> [VARIABLE=value ...]"
	@echo ""
	@echo "System & General:"
	@echo "  help                 - Show this help message."
	@echo "  system-health        - Display system uptime, disk usage, and memory usage."
	@echo ""
	@echo "Networking:"
	@echo "  network-interfaces   - Show network interface configurations."
	@echo "  network-ports        - Show listening TCP and UDP ports (requires sudo)."
	@echo "  network-ping         - Ping default target (${TARGET_HOST}). Usage: make network-ping TARGET_HOST=yourhost.com"
	@echo "  network-dns-lookup   - DNS lookup for default target (${TARGET_HOST}). Usage: make network-dns-lookup TARGET_HOST=yourhost.com"
	@echo ""
	@echo "Kubernetes (kubectl):"
	@echo "  k8s-cluster-info     - Display Kubernetes cluster information and version."
	@echo "  k8s-nodes            - List all nodes in the cluster with details."
	@echo "  k8s-all-pods         - List all pods in all namespaces with details."
	@echo "  k8s-ns-pods          - List pods in a specific namespace (NS=${NS}). Usage: make k8s-ns-pods NS=my-namespace"
	@echo "  k8s-events           - Get events in a namespace (NS=${NS}), sorted by time. Usage: make k8s-events NS=my-namespace"
	@echo "  k8s-services         - List all services in all namespaces."
	@echo "  k8s-ns-services      - List services in a specific namespace (NS=${NS}). Usage: make k8s-ns-services NS=my-namespace"
	@echo "  k8s-logs             - Tail logs from a pod (POD=<pod> [NS=<namespace>] [CONTAINER=<container>])."
	@echo "  k8s-shell            - Open a shell into a pod (POD=<pod> [NS=<namespace>] [CONTAINER=<container>])."
	@echo "  k8s-port-forward     - Forward a local port to a service (SVC=<svc> [NS=<namespace>] LOCAL_PORT=${LOCAL_PORT} REMOTE_PORT=${REMOTE_PORT})."
	@echo "  k8s-top-nodes        - Show resource usage for nodes (requires metrics-server)."
	@echo "  k8s-top-pods         - Show resource usage for pods in a namespace (NS=${NS}) (requires metrics-server)."
	@echo ""
	@echo "Docker:"
	@echo "  docker-info          - List running containers, all containers, images, and Docker disk usage."
	@echo "  docker-stats         - Display live resource usage for all running containers. Ctrl+C to exit."
	@echo "  docker-logs          - Tail logs from a container (CONTAINER=<container_id_or_name>)."
	@echo "  docker-shell         - Open a shell into a container (CONTAINER=<container_id_or_name>)."
	@echo ""
	@echo "Remote Access Services:"
	@echo "  tailscale-status     - Check Tailscale status and IP (requires sudo)."
	@echo "  cloudflare-status    - Check Cloudflare tunnel status. Usage: make cloudflare-status [CLOUDFLARE_TUNNEL_NAME=your-tunnel]"
	@echo ""

# System & General
system-health:
	@echo "--- System Uptime & Load ---"
	@uptime
	@echo "\n--- Disk Usage ---"
	@df -h
	@echo "\n--- Memory Usage ---"
	@free -m

# Networking
network-interfaces:
	@echo "--- Network Interfaces (ip addr) ---"
	@ip addr show
	@echo "\n--- Network Interfaces (hostname -I) ---"
	@hostname -I

network-ports:
	@echo "--- Listening Ports (ss -tulnp) ---"
	@sudo ss -tulnp

network-ping:
	@echo "--- Pinging ${TARGET_HOST} ---"
	@ping -c 4 ${TARGET_HOST}

network-dns-lookup:
	@echo "--- DNS Lookup for ${TARGET_HOST} (using dig) ---"
	@dig ${TARGET_HOST} || nslookup ${TARGET_HOST}


# Kubernetes
k8s-cluster-info:
	@echo "--- Kubernetes Cluster Info ---"
	@kubectl cluster-info
	@echo "\n--- Kubernetes Version ---"
	@kubectl version --short

k8s-nodes:
	@echo "--- Kubernetes Nodes ---"
	@kubectl get nodes -o wide

k8s-all-pods:
	@echo "--- Kubernetes Pods (All Namespaces) ---"
	@kubectl get pods -A -o wide

k8s-ns-pods:
	@echo "--- Kubernetes Pods (Namespace: ${NS}) ---"
	@kubectl get pods -n ${NS} -o wide

k8s-events:
	@echo "--- Kubernetes Events (Namespace: ${NS}, sorted by time) ---"
	@kubectl get events -n ${NS} --sort-by=.metadata.creationTimestamp

k8s-services:
	@echo "--- Kubernetes Services (All Namespaces) ---"
	@kubectl get services -A -o wide

k8s-ns-services:
	@echo "--- Kubernetes Services (Namespace: ${NS}) ---"
	@kubectl get services -n ${NS} -o wide

k8s-logs:
	@if [ -z "${POD}" ]; then \
		echo "Usage: make k8s-logs POD=<pod_name> [NS=<namespace>] [CONTAINER=<container_name>]"; \
		exit 1; \
	fi
	@echo "--- Tailing logs for Pod: ${POD}, Namespace: ${NS} $(if $(CONTAINER),Container: $(CONTAINER),) ---"
	@kubectl logs -f ${POD} -n ${NS} $(if $(CONTAINER),-c $(CONTAINER),)

k8s-shell:
	@if [ -z "${POD}" ]; then \
		echo "Usage: make k8s-shell POD=<pod_name> [NS=<namespace>] [CONTAINER=<container_name>]"; \
		exit 1; \
	fi
	@echo "--- Opening shell into Pod: ${POD}, Namespace: ${NS} $(if $(CONTAINER),Container: $(CONTAINER),) ---"
	@kubectl exec -it ${POD} -n ${NS} $(if $(CONTAINER),-c $(CONTAINER),) -- /bin/sh -c "[ -x /bin/bash ] && /bin/bash || /bin/sh"

k8s-port-forward:
	@if [ -z "${SVC}" ]; then \
		echo "Usage: make k8s-port-forward SVC=<service_name> [NS=<namespace>] [LOCAL_PORT=<local_port>] [REMOTE_PORT=<remote_port>]"; \
		exit 1; \
	fi
	@echo "--- Port-forwarding Service: ${SVC}, Namespace: ${NS} from local ${LOCAL_PORT} to service ${REMOTE_PORT} ---"
	@echo "Access at: http://localhost:${LOCAL_PORT}"
	@kubectl port-forward service/${SVC} -n ${NS} ${LOCAL_PORT}:${REMOTE_PORT}

k8s-top-nodes:
	@echo "--- Kubernetes Node Resource Usage (requires metrics-server) ---"
	@kubectl top nodes

k8s-top-pods:
	@echo "--- Kubernetes Pod Resource Usage (Namespace: ${NS}, requires metrics-server) ---"
	@kubectl top pods -n ${NS}

# Docker
docker-info:
	@echo "--- Running Docker Containers (docker ps) ---"
	@docker ps
	@echo "\n--- All Docker Containers (docker ps -a) ---"
	@docker ps -a
	@echo "\n--- Docker Images (docker images) ---"
	@docker images
	@echo "\n--- Docker Disk Usage (docker system df) ---"
	@docker system df

docker-stats:
	@echo "--- Docker Container Stats (Ctrl+C to exit) ---"
	@docker stats

docker-logs:
	@if [ -z "${CONTAINER}" ]; then \
		echo "Usage: make docker-logs CONTAINER=<container_id_or_name>"; \
		exit 1; \
	fi
	@echo "--- Tailing logs for Docker Container: ${CONTAINER} ---"
	@docker logs -f ${CONTAINER}

docker-shell:
	@if [ -z "${CONTAINER}" ]; then \
		echo "Usage: make docker-shell CONTAINER=<container_id_or_name>"; \
		exit 1; \
	fi
	@echo "--- Opening shell into Docker Container: ${CONTAINER} ---"
	@docker exec -it ${CONTAINER} /bin/sh -c "[ -x /bin/bash ] && /bin/bash || /bin/sh"

# Remote Access Services
tailscale-status:
	@echo "--- Tailscale Status ---"
	@sudo tailscale status
	@echo "\n--- Tailscale IP ---"
	@sudo tailscale ip -4 || sudo tailscale ip

cloudflare-status:
	@echo "--- Cloudflare Tunnel Service Status (systemctl) ---"
	@sudo systemctl status cloudflared --no-pager
	@echo "\n--- Cloudflare Tunnel List ---"
	@cloudflared tunnel list
	@echo "\n--- Cloudflare Tunnel Info (${CLOUDFLARE_TUNNEL_NAME}) ---"
	@echo "If tunnel name is not '${CLOUDFLARE_TUNNEL_NAME}', use: make cloudflare-status CLOUDFLARE_TUNNEL_NAME=<your-tunnel-name>"
	@cloudflared tunnel info ${CLOUDFLARE_TUNNEL_NAME} > /dev/null 2>&1 && cloudflared tunnel info ${CLOUDFLARE_TUNNEL_NAME} || echo "Failed to get info for ${CLOUDFLARE_TUNNEL_NAME}. Ensure tunnel name is correct and you are logged in via 'cloudflared tunnel login'."
