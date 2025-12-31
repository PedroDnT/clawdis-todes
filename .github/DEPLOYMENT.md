# Deployment Setup Guide

Quick reference for setting up GitHub Actions deployments for Clawdis.

## Quick Start Checklist

- [ ] Fork/clone repository
- [ ] Enable GitHub Actions
- [ ] Set up GitHub Secrets (see below)
- [ ] Run Docker Build workflow to publish images
- [ ] Run deployment workflow to deploy

## Required GitHub Secrets

### For Docker Deployment

Go to **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `DEPLOY_SSH_KEY` | SSH private key for VM access | `cat ~/.ssh/clawdis-deploy` |
| `DEPLOY_HOST` | VM hostname or IP address | Your VM's IP or domain |
| `DEPLOY_USER` | SSH username | Usually `clawdis` or your user |

### Optional Secrets (Recommended)

| Secret Name | Description | How to Generate |
|-------------|-------------|-----------------|
| `CLAWDIS_GATEWAY_TOKEN` | Gateway authentication token | `openssl rand -hex 32` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | [@BotFather](https://t.me/botfather) |
| `DISCORD_BOT_TOKEN` | Discord bot token | [Discord Developer Portal](https://discord.com/developers/applications) |

## Step-by-Step Setup

### 1. Generate SSH Key

On your local machine:
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/clawdis-deploy
```

### 2. Add Public Key to VM

```bash
# Copy public key to VM
ssh-copy-id -i ~/.ssh/clawdis-deploy.pub user@your-vm-ip

# Or manually:
cat ~/.ssh/clawdis-deploy.pub | ssh user@your-vm-ip 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

### 3. Add Private Key to GitHub

```bash
# Display private key
cat ~/.ssh/clawdis-deploy

# Copy the entire output (including BEGIN/END lines)
# Add to GitHub: Settings → Secrets → DEPLOY_SSH_KEY
```

### 4. Add Other Secrets to GitHub

```bash
# Generate gateway token
openssl rand -hex 32
# Add to GitHub: Settings → Secrets → CLAWDIS_GATEWAY_TOKEN

# Add your VM info
# DEPLOY_HOST: your-vm-ip or domain.com
# DEPLOY_USER: clawdis (or your username)
```

### 5. Test Deployment

1. Go to **Actions** tab
2. Select **Deploy via Docker** workflow
3. Click **Run workflow**
4. Select `development` environment
5. Click **Run workflow**
6. Monitor the logs

## Environment Setup (Optional but Recommended)

For production deployments, set up environments:

1. Go to **Settings → Environments**
2. Click **New environment**
3. Name: `production`
4. Add protection rules:
   - ✅ Required reviewers (select team members)
   - ✅ Deployment branches: `main` only
5. Repeat for `staging` and `development` if needed

### Environment-Specific Secrets

You can override secrets per environment:

1. Go to **Settings → Environments → production**
2. Click **Add secret**
3. Add environment-specific values (e.g., different VMs per environment)

## Workflows Overview

### 1. Docker Build & Publish
- **File**: `.github/workflows/docker-publish.yml`
- **Triggers**: Push to main, version tags, PRs
- **Purpose**: Builds and publishes Docker images to GitHub Container Registry
- **Manual run**: Yes, via workflow_dispatch

### 2. Deploy to VM
- **File**: `.github/workflows/deploy-vm.yml`
- **Triggers**: Manual only (workflow_dispatch)
- **Purpose**: Deploys to VM using systemd/native install
- **Options**: Choose environment, restart-only mode

### 3. Deploy via Docker
- **File**: `.github/workflows/deploy-docker.yml`
- **Triggers**: Manual only (workflow_dispatch)
- **Purpose**: Deploys Docker container to VM
- **Options**: Choose environment, image tag

## Testing Your Setup

### Test SSH Connection
```bash
# From your local machine
ssh -i ~/.ssh/clawdis-deploy user@your-vm-ip "echo 'SSH connection successful'"
```

### Test Docker Image Pull
```bash
# This tests if the image is publicly accessible
docker pull ghcr.io/OWNER/REPO:latest

# For private repos, login first:
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Test Service Restart
```bash
# SSH into VM
ssh user@your-vm-ip

# Test systemd restart
sudo systemctl restart clawdis-gateway.service
sudo systemctl status clawdis-gateway.service

# Or test Docker restart
docker restart clawdis-gateway
docker ps --filter name=clawdis-gateway
```

## Troubleshooting

### "Permission denied (publickey)"
- Verify SSH key is added to GitHub Secrets correctly
- Check key is in VM's `~/.ssh/authorized_keys`
- Ensure correct permissions: `chmod 600 ~/.ssh/authorized_keys`

### "Image not found" when deploying
- Wait for Docker Build workflow to complete first
- Check image exists in Packages tab
- Verify GITHUB_TOKEN has packages:read permission

### Deployment succeeds but service won't start
- SSH into VM and check logs:
  ```bash
  # For systemd
  sudo journalctl -u clawdis-gateway.service -n 50

  # For Docker
  docker logs clawdis-gateway
  ```
- Common issues: missing credentials, wrong configuration, port conflicts

### Need to rollback?
See [GitHub Deployment Guide](../docs/github-deployment.md#rollback-procedures)

## Next Steps

1. ✅ Complete checklist above
2. 📖 Read full [GitHub Deployment Guide](../docs/github-deployment.md)
3. 🚀 Run your first deployment
4. 📊 Monitor logs and verify service health
5. 🔒 Review [Security Guidelines](../docs/security.md)

## Quick Links

- [Full GitHub Deployment Guide](../docs/github-deployment.md)
- [VM Deployment Guide](../docs/vm-deployment.md)
- [Docker Deployment Guide](../docs/docker-deployment.md)
- [Configuration Reference](../docs/configuration.md)
