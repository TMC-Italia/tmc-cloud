.PHONY: help env network master worker monitoring backup runner tailscale cloudflare health sync clean \
        dc-up dc-down dc-logs dc-ps ping-master ping-worker1 ping-worker2 ping-storage netstat ifconfig

help:
	@echo "TMC-Cloud Makefile - Common commands:"
	@echo "  make env           # Run environment setup"
	@echo "  make network       # Configure network"
	@echo "  make master        # Setup Kubernetes master node"
	@echo "  make worker        # Setup Kubernetes worker node"
	@echo "  make monitoring    # Deploy monitoring stack"
	@echo "  make backup        # Setup backup system"
	@echo "  make runner        # Setup GitHub Actions runner"
	@echo "  make tailscale     # Setup Tailscale VPN"
	@echo "  make cloudflare    # Setup Cloudflare Tunnel"
	@echo "  make health        # Run system health check"
	@echo "  make sync          # Sync/create repo directory structure"
	@echo "  make clean         # Remove generated logs and temp files"
	@echo ""
	@echo "Docker Compose (development stack):"
	@echo "  make dc-up         # Start dev stack (docker-compose up -d)"
	@echo "  make dc-down       # Stop dev stack (docker-compose down)"
	@echo "  make dc-logs       # Show logs for dev stack"
	@echo "  make dc-ps         # Show running containers"
	@echo ""
	@echo "Networking/Infra checks:"
	@echo "  make ping-master   # Ping master node"
	@echo "  make ping-worker1  # Ping worker1 node"
	@echo "  make ping-worker2  # Ping worker2 node"
	@echo "  make ping-storage  # Ping storage node"
	@echo "  make netstat       # Show open ports"
	@echo "  make ifconfig      # Show network interfaces"

env:
	./scripts/setup-environment.sh

network:
	./scripts/configure-network.sh

master:
	./scripts/setup-master.sh

worker:
	./scripts/setup-worker.sh

monitoring:
	./scripts/deploy-monitoring.sh

backup:
	./scripts/setup-backup.sh

runner:
	./scripts/setup-github-runner.sh

tailscale:
	./scripts/setup-tailscale.sh

cloudflare:
	./scripts/setup-cloudflare.sh

health:
	./scripts/maintenance/system-health-check.sh

sync:
	./scripts/sync_structure.sh

clean:
	rm -rf logs/* on-premises-cloud/logs/* || true

# Docker Compose commands for development stack
dc-up:
	docker compose -f docker/compose/development.yml up -d

dc-down:
	docker compose -f docker/compose/development.yml down

dc-logs:
	docker compose -f docker/compose/development.yml logs -f

dc-ps:
	docker compose -f docker/compose/development.yml ps

# Networking/infra checks
ping-master:
	ping -c 4 192.168.1.100

ping-worker1:
	ping -c 4 192.168.1.101

ping-worker2:
	ping -c 4 192.168.1.102

ping-storage:
	ping -c 4 192.168.1.103

netstat:
	netstat -tulnp | grep LISTEN || ss -tulnp | grep LISTEN

ifconfig:
	ifconfig || ip addr
