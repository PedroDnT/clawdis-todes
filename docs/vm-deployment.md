---
summary: "Complete guide for deploying Clawdis Gateway in a VM"
read_when:
  - Setting up Clawdis in a cloud VM or VPS
  - Running Clawdis as a headless service
  - Production deployment setup
---

# VM Deployment Guide

This guide covers deploying Clawdis Gateway as a persistent service in a Linux VM (cloud VPS, dedicated server, etc.).

## Prerequisites

### System Requirements
- **OS**: Ubuntu 22.04+ / Debian 12+ / RHEL 9+ (any modern Linux with systemd)
- **Node.js**: ≥22.12.0
- **pnpm**: 10.23.0+
- **Memory**: 512MB minimum, 1GB+ recommended
- **Disk**: 2GB+ for dependencies and logs
- **Network**: Ports 18789 (gateway WS), 18790 (optional bridge), 18793 (canvas host)

### Domain / Access
- **SSH access** to the VM
- **Tailscale** (recommended) or VPN for secure remote access
- Alternatively: reverse proxy (nginx/caddy) with TLS for HTTPS/WSS

## Installation Steps

### 1. Create Service User
```bash
# Create dedicated user (no login shell for security)
sudo useradd -r -s /bin/bash -d /opt/clawdis -m clawdis

# Switch to service user for setup
sudo -u clawdis -i
```

### 2. Install Node.js (if not present)
```bash
# Using nvm (recommended for user-level install)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22

# OR system-wide via NodeSource (requires root)
# curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
# sudo apt-get install -y nodejs
```

### 3. Install pnpm
```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -
source ~/.bashrc
```

### 4. Clone and Build Clawdis
```bash
cd /opt/clawdis
git clone https://github.com/steipete/clawdis.git app
cd app

# Install dependencies
pnpm install

# Build TypeScript
pnpm build

# Build control UI (optional but recommended)
pnpm ui:build

# Link globally for the clawdis user
pnpm link --global
```

### 5. Initial Configuration

Create the configuration directory:
```bash
mkdir -p ~/.clawdis
```

Create `~/.clawdis/clawdis.json`:
```json
{
  "routing": {
    "allowFrom": ["+1234567890"]
  },
  "gateway": {
    "port": 18789,
    "bindPolicy": "loopback"
  },
  "telegram": {
    "botToken": "YOUR_BOT_TOKEN"
  },
  "discord": {
    "token": "YOUR_DISCORD_TOKEN"
  },
  "agent": {
    "workspace": "/opt/clawdis/clawd"
  }
}
```

### 6. Link WhatsApp (Interactive)
```bash
# This requires interactive terminal for QR code
pnpm clawdis login
# Scan the QR code with WhatsApp on your phone
```

**Note**: WhatsApp credentials are stored in `~/.clawdis/credentials/`. Back this up securely.

## systemd Service Setup

### 1. Create Service File
As root, create `/etc/systemd/system/clawdis-gateway.service`:

```ini
[Unit]
Description=Clawdis Gateway - Personal AI Assistant
Documentation=https://github.com/steipete/clawdis
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=clawdis
Group=clawdis
WorkingDirectory=/opt/clawdis/app

# Use the globally-linked clawdis binary
ExecStart=/opt/clawdis/.local/share/pnpm/clawdis gateway --port 18789

# Restart policy
Restart=on-failure
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=300

# Environment
Environment="NODE_ENV=production"
Environment="PATH=/opt/clawdis/.nvm/versions/node/v22.12.0/bin:/usr/local/bin:/usr/bin:/bin"
# Optional: set gateway token for auth
# Environment="CLAWDIS_GATEWAY_TOKEN=your-secret-token"

# Security hardening
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/opt/clawdis

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=clawdis-gateway

# Resource limits (adjust as needed)
MemoryMax=1G
TasksMax=256

[Install]
WantedBy=multi-user.target
```

### 2. Enable and Start Service
```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable clawdis-gateway.service

# Start the service
sudo systemctl start clawdis-gateway.service

# Check status
sudo systemctl status clawdis-gateway.service
```

### 3. View Logs
```bash
# Follow live logs
sudo journalctl -u clawdis-gateway.service -f

# Last 100 lines
sudo journalctl -u clawdis-gateway.service -n 100

# Logs since last boot
sudo journalctl -u clawdis-gateway.service -b
```

## Remote Access

### Option 1: Tailscale (Recommended)
```bash
# Install Tailscale on the VM
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# On your local machine, connect via Tailscale IP
# Example: ws://100.64.1.2:18789
```

### Option 2: SSH Tunnel
```bash
# From local machine
ssh -N -L 18789:127.0.0.1:18789 clawdis@your-vm-ip

# Then connect to ws://127.0.0.1:18789 locally
```

### Option 3: Reverse Proxy (nginx)
**Warning**: Only use with proper TLS and authentication.

Create `/etc/nginx/sites-available/clawdis`:
```nginx
upstream clawdis_gateway {
    server 127.0.0.1:18789;
}

server {
    listen 443 ssl http2;
    server_name clawdis.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/clawdis.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/clawdis.yourdomain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;

    # WebSocket upgrade
    location / {
        proxy_pass http://clawdis_gateway;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
```

Enable and reload:
```bash
sudo ln -s /etc/nginx/sites-available/clawdis /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Security Considerations

### 1. Gateway Token Authentication
Set a strong token in the systemd service:
```bash
sudo systemctl edit clawdis-gateway.service
```

Add:
```ini
[Service]
Environment="CLAWDIS_GATEWAY_TOKEN=$(openssl rand -hex 32)"
```

Clients must include this token in the `connect` handshake:
```json
{
  "type": "req",
  "id": "1",
  "method": "connect",
  "params": {
    "auth": {
      "token": "your-generated-token"
    }
  }
}
```

### 2. Firewall Rules
```bash
# Allow SSH only
sudo ufw allow 22/tcp

# If using Tailscale, deny external access to gateway ports
sudo ufw deny 18789/tcp
sudo ufw deny 18790/tcp
sudo ufw deny 18793/tcp

sudo ufw enable
```

### 3. Credential Backup
```bash
# Backup WhatsApp credentials
sudo tar -czf clawdis-credentials-$(date +%Y%m%d).tar.gz \
  -C /opt/clawdis/.clawdis credentials/

# Store securely off-server
scp clawdis-credentials-*.tar.gz backup-server:/backups/
```

## Maintenance

### Update Clawdis
```bash
# As clawdis user
sudo -u clawdis -i
cd /opt/clawdis/app

# Pull latest
git pull origin main

# Rebuild
pnpm install
pnpm build
pnpm ui:build

# Restart service
exit
sudo systemctl restart clawdis-gateway.service
```

### Monitor Health
```bash
# Check gateway health
curl http://localhost:18789  # Should see upgrade required or health endpoint

# Or use clawdis CLI
sudo -u clawdis pnpm clawdis health

# System resource usage
sudo systemctl status clawdis-gateway.service
```

### Restart Gateway
```bash
# Graceful restart (sends shutdown event to clients)
sudo systemctl restart clawdis-gateway.service

# Or via SIGUSR1 (in-process restart)
sudo systemctl kill -s SIGUSR1 clawdis-gateway.service
```

### Log Rotation
systemd journal handles rotation automatically, but you can configure limits:

```bash
sudo vim /etc/systemd/journald.conf
```

Set:
```ini
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
```

Then:
```bash
sudo systemctl restart systemd-journald
```

## Troubleshooting

### Service Won't Start
```bash
# Check detailed status
sudo systemctl status clawdis-gateway.service

# Check logs for errors
sudo journalctl -u clawdis-gateway.service -n 50 --no-pager

# Common issues:
# - Node version: verify PATH includes correct node
# - Permissions: ensure /opt/clawdis is owned by clawdis user
# - Port conflict: check if 18789 is in use
sudo lsof -i :18789
```

### WhatsApp Disconnected
```bash
# Re-link WhatsApp
sudo -u clawdis -i
cd /opt/clawdis/app
pnpm clawdis login

# Restart service
exit
sudo systemctl restart clawdis-gateway.service
```

### High Memory Usage
```bash
# Check current usage
systemctl status clawdis-gateway.service

# Adjust MemoryMax in service file if needed
sudo systemctl edit clawdis-gateway.service

# Add or modify:
[Service]
MemoryMax=2G
```

### Cannot Connect Remotely
```bash
# Verify service is running
sudo systemctl status clawdis-gateway.service

# Check bind address (should see 127.0.0.1:18789)
sudo netstat -tlnp | grep 18789

# Test local connection
curl http://localhost:18789

# If using Tailscale, verify connectivity
tailscale status
ping <tailscale-ip>
```

## Advanced: Multi-Instance Setup

Run multiple gateway instances on different ports:

```bash
# Copy service file for instance 2
sudo cp /etc/systemd/system/clawdis-gateway.service \
       /etc/systemd/system/clawdis-gateway@.service

# Modify to use instance parameter
ExecStart=/opt/clawdis/.local/share/pnpm/clawdis gateway --port 18%i

# Start instance on port 18790
sudo systemctl start clawdis-gateway@790.service
```

## Related Documentation

- [Gateway Protocol](gateway.md)
- [Configuration Reference](configuration.md)
- [Security Guidelines](security.md)
- [Troubleshooting Guide](troubleshooting.md)
- [Tailscale Setup](tailscale.md)
