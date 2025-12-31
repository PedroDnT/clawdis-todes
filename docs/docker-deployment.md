---
summary: "Docker deployment guide for Clawdis Gateway"
read_when:
  - Deploying Clawdis with Docker
  - Container-based deployment
---

# Docker Deployment Guide

This guide covers deploying Clawdis Gateway using Docker and Docker Compose.

## Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+ (or `docker compose` plugin)

### 1. Build and Run with Docker Compose

```bash
# Clone the repository
git clone https://github.com/steipete/clawdis.git
cd clawdis

# Start the gateway
docker compose up -d

# View logs
docker compose logs -f clawdis-gateway

# Check status
docker compose ps
```

### 2. Link WhatsApp

WhatsApp linking requires an interactive terminal to scan the QR code:

```bash
# Run login command in the container
docker compose exec clawdis-gateway pnpm clawdis login

# Scan the QR code with your phone
# Credentials will be persisted in the clawdis-config volume
```

### 3. Configure

Create a `clawdis.json` file in your project directory:

```json
{
  "routing": {
    "allowFrom": ["+1234567890"]
  },
  "telegram": {
    "botToken": "YOUR_BOT_TOKEN"
  },
  "discord": {
    "token": "YOUR_DISCORD_TOKEN"
  }
}
```

Mount it in `docker-compose.yml`:

```yaml
volumes:
  - ./clawdis.json:/home/clawdis/.clawdis/clawdis.json:ro
```

Restart:

```bash
docker compose restart
```

## Environment Variables

You can configure Clawdis via environment variables in `docker-compose.yml`:

```yaml
environment:
  # Gateway authentication
  - CLAWDIS_GATEWAY_TOKEN=your-secret-token-here

  # Provider tokens (optional, can also be in config file)
  - TELEGRAM_BOT_TOKEN=123456:ABCDEF
  - DISCORD_BOT_TOKEN=your-discord-token

  # Timezone
  - TZ=America/New_York
```

## Data Persistence

Docker Compose creates two named volumes for data persistence:

- **clawdis-config**: Stores credentials, configuration, and session data
  - Location: `~/.clawdis/` in container
  - Contains: WhatsApp credentials, Telegram auth, config files

- **clawdis-workspace**: Agent workspace directory
  - Location: `~/clawd/` in container
  - Contains: Agent files, skills, canvas data

### Backup Volumes

```bash
# Backup config (includes WhatsApp credentials)
docker run --rm -v clawdis-config:/data -v $(pwd):/backup \
  alpine tar czf /backup/clawdis-config-backup.tar.gz -C /data .

# Backup workspace
docker run --rm -v clawdis-workspace:/data -v $(pwd):/backup \
  alpine tar czf /backup/clawdis-workspace-backup.tar.gz -C /data .
```

### Restore Volumes

```bash
# Restore config
docker run --rm -v clawdis-config:/data -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/clawdis-config-backup.tar.gz"

# Restore workspace
docker run --rm -v clawdis-workspace:/data -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/clawdis-workspace-backup.tar.gz"
```

## Production Deployment

### Using Docker without Compose

```bash
# Build the image
docker build -t clawdis-gateway:latest .

# Create volumes
docker volume create clawdis-config
docker volume create clawdis-workspace

# Run container
docker run -d \
  --name clawdis-gateway \
  --restart unless-stopped \
  -p 127.0.0.1:18789:18789 \
  -p 127.0.0.1:18790:18790 \
  -p 127.0.0.1:18793:18793 \
  -v clawdis-config:/home/clawdis/.clawdis \
  -v clawdis-workspace:/home/clawdis/clawd \
  -e NODE_ENV=production \
  -e CLAWDIS_GATEWAY_TOKEN=your-secret-token \
  --memory=1g \
  --cpus=1.0 \
  clawdis-gateway:latest
```

### With Reverse Proxy (Traefik)

Add labels to `docker-compose.yml`:

```yaml
services:
  clawdis-gateway:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.clawdis.rule=Host(`clawdis.yourdomain.com`)"
      - "traefik.http.routers.clawdis.entrypoints=websecure"
      - "traefik.http.routers.clawdis.tls.certresolver=letsencrypt"
      - "traefik.http.services.clawdis.loadbalancer.server.port=18789"

    networks:
      - traefik-public
      - default

networks:
  traefik-public:
    external: true
```

## Monitoring

### Health Check

Docker includes a built-in health check:

```bash
# View health status
docker inspect --format='{{.State.Health.Status}}' clawdis-gateway

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' clawdis-gateway
```

### Resource Usage

```bash
# Real-time stats
docker stats clawdis-gateway

# Detailed inspection
docker inspect clawdis-gateway
```

### Logs

```bash
# Follow logs
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100

# Specific service
docker compose logs -f clawdis-gateway

# Since timestamp
docker compose logs --since 2024-01-01T12:00:00
```

## Maintenance

### Update Clawdis

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker compose down
docker compose build --no-cache
docker compose up -d

# Or with one command (rebuild if changed)
docker compose up -d --build
```

### Restart Gateway

```bash
# Graceful restart
docker compose restart clawdis-gateway

# Or
docker restart clawdis-gateway
```

### Clean Up

```bash
# Stop and remove containers (keeps volumes)
docker compose down

# Remove containers and volumes (WARNING: deletes all data)
docker compose down -v

# Remove unused images
docker image prune -a
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs clawdis-gateway

# Check container status
docker compose ps

# Inspect container
docker inspect clawdis-gateway
```

### WhatsApp Disconnected

```bash
# Re-link WhatsApp
docker compose exec clawdis-gateway pnpm clawdis login

# Restart container
docker compose restart clawdis-gateway
```

### Permission Issues

The container runs as user `clawdis` (UID 1000). If you mount local directories, ensure they're writable:

```bash
# Fix permissions on host
chown -R 1000:1000 ./clawdis-data
```

### Network Issues

If the gateway can't be reached:

```bash
# Check port bindings
docker port clawdis-gateway

# Test from inside container
docker compose exec clawdis-gateway curl http://localhost:18789

# Test from host
curl http://localhost:18789
```

### Out of Memory

Increase memory limit in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 2G
```

Or with `docker run`:

```bash
docker run --memory=2g ...
```

## Security Considerations

### 1. Network Isolation

Bind to loopback only (already configured):

```yaml
ports:
  - "127.0.0.1:18789:18789"  # Only accessible from localhost
```

For remote access, use SSH tunnel or VPN:

```bash
# SSH tunnel
ssh -N -L 18789:127.0.0.1:18789 user@docker-host
```

### 2. Gateway Token

Always set a strong authentication token:

```bash
# Generate token
openssl rand -hex 32

# Set in docker-compose.yml
environment:
  - CLAWDIS_GATEWAY_TOKEN=<generated-token>
```

### 3. Secrets Management

Use Docker secrets instead of environment variables for sensitive data:

```yaml
services:
  clawdis-gateway:
    secrets:
      - gateway_token
      - telegram_token

secrets:
  gateway_token:
    file: ./secrets/gateway_token.txt
  telegram_token:
    file: ./secrets/telegram_token.txt
```

### 4. Read-Only Root Filesystem

Add to `docker-compose.yml` for extra security:

```yaml
security_opt:
  - no-new-privileges:true
read_only: true
tmpfs:
  - /tmp
```

## Multi-Stage Builds

The Dockerfile uses multi-stage builds to reduce image size:

- **Builder stage**: Installs dev dependencies and builds TypeScript
- **Production stage**: Only includes runtime dependencies and built code

Final image size: ~300MB (vs ~800MB without multi-stage)

## Alternative: Prebuilt Images

If you want to avoid building locally, you can create a CI/CD pipeline to build and push to a registry:

```bash
# Build and tag
docker build -t your-registry.com/clawdis-gateway:latest .

# Push to registry
docker push your-registry.com/clawdis-gateway:latest

# Pull and run on server
docker pull your-registry.com/clawdis-gateway:latest
docker run -d ... your-registry.com/clawdis-gateway:latest
```

## Orchestration

### Docker Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml clawdis

# Check services
docker service ls
docker service logs clawdis_clawdis-gateway
```

### Kubernetes

For Kubernetes deployment, convert the Docker Compose file:

```bash
# Install kompose
curl -L https://github.com/kubernetes/kompose/releases/download/v1.31.0/kompose-linux-amd64 -o kompose
chmod +x kompose
sudo mv kompose /usr/local/bin

# Convert
kompose convert -f docker-compose.yml

# Apply
kubectl apply -f clawdis-gateway-deployment.yaml
kubectl apply -f clawdis-gateway-service.yaml
```

## Comparison: Docker vs Systemd

| Feature | Docker | systemd (VM) |
|---------|--------|--------------|
| Isolation | ✅ Container isolation | ❌ Runs on host |
| Portability | ✅ Works anywhere | ⚠️ Linux-specific |
| Resource limits | ✅ Easy with Docker | ⚠️ Requires cgroups config |
| Backups | ✅ Volume snapshots | ⚠️ Manual file backups |
| Debugging | ⚠️ Extra layer | ✅ Direct access |
| Performance | ⚠️ Small overhead | ✅ Native |

**Recommendation**: Use Docker for quick deployments and easy migration. Use systemd for maximum performance and direct system access.

## Related Documentation

- [VM Deployment Guide](vm-deployment.md)
- [Gateway Protocol](gateway.md)
- [Configuration Reference](configuration.md)
- [Security Guidelines](security.md)
