---
summary: "Deploy Clawdis using GitHub Actions and GitHub Container Registry"
read_when:
  - Setting up automated deployments
  - Using GitHub Actions for CI/CD
  - Deploying from GitHub Container Registry
---

# GitHub Deployment Guide

This guide covers deploying Clawdis using GitHub Actions workflows, GitHub Container Registry (GHCR), and automated VM deployments.

## Overview

Clawdis includes three GitHub Actions workflows for deployment:

1. **Docker Build & Publish** - Automatically builds and publishes Docker images to GHCR
2. **Deploy to VM** - Deploys to a VM using SSH (systemd/native)
3. **Deploy via Docker** - Deploys Docker containers to a remote host

## Prerequisites

### For All Workflows
- GitHub repository with Actions enabled
- Appropriate permissions (packages: write for GHCR)

### For VM Deployment
- Linux VM with SSH access
- Clawdis installed via systemd (see [VM Deployment](vm-deployment.md))
- SSH key for deployment

### For Docker Deployment
- Linux VM with Docker installed
- SSH access to the VM
- Docker permissions for deployment user

## Workflow 1: Docker Build & Publish

### What It Does
- Builds multi-platform Docker images (amd64, arm64)
- Publishes to GitHub Container Registry (ghcr.io)
- Triggered on:
  - Push to `main` branch
  - Version tags (`v*.*.*`)
  - Pull requests (build only, no push)
  - Manual trigger via workflow_dispatch

### Setup

#### 1. Enable GitHub Packages
This is enabled by default for public repositories. For private repos:
- Go to Settings → Actions → General
- Under "Workflow permissions", enable "Read and write permissions"

#### 2. Image Tags
Images are automatically tagged based on:
- `latest` - Latest main branch build
- `v1.2.3` - Semantic version tags
- `main-<sha>` - Branch name with commit SHA
- `pr-123` - Pull request number

### Usage

#### Automatic Builds
Push to main or create a version tag:
```bash
# Trigger build on main
git push origin main

# Create and push version tag
git tag v2.0.0
git push origin v2.0.0
```

#### Manual Trigger
1. Go to Actions → Docker Build and Publish
2. Click "Run workflow"
3. Select branch
4. Click "Run workflow"

#### Pull Images
```bash
# Latest
docker pull ghcr.io/OWNER/REPO:latest

# Specific version
docker pull ghcr.io/OWNER/REPO:v2.0.0

# By SHA
docker pull ghcr.io/OWNER/REPO:main-abc1234
```

### Customize Build

Edit `.github/workflows/docker-publish.yml`:

```yaml
# Change platforms
platforms: linux/amd64,linux/arm64,linux/arm/v7

# Add build arguments
build-args: |
  NODE_ENV=production
  CUSTOM_ARG=value
```

## Workflow 2: Deploy to VM

### What It Does
- SSHs into your VM
- Pulls latest code from GitHub
- Runs `pnpm install` and `pnpm build`
- Restarts the systemd service
- Verifies deployment success

### Setup

#### 1. Prepare Your VM
First, set up Clawdis on your VM using the automated script:

```bash
# On your VM
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/scripts/vm-deploy.sh | sudo bash
```

Or follow the [VM Deployment Guide](vm-deployment.md).

#### 2. Create SSH Key for Deployment
```bash
# On your local machine
ssh-keygen -t ed25519 -C "github-deploy" -f ~/.ssh/clawdis-deploy
```

Copy the public key to your VM:
```bash
ssh-copy-id -i ~/.ssh/clawdis-deploy.pub user@your-vm-ip
```

#### 3. Configure GitHub Secrets
Go to Settings → Secrets and variables → Actions → New repository secret:

| Secret Name | Value | Example |
|-------------|-------|---------|
| `DEPLOY_SSH_KEY` | Private key content | Contents of `~/.ssh/clawdis-deploy` |
| `DEPLOY_HOST` | VM hostname or IP | `clawdis.example.com` or `192.0.2.1` |
| `DEPLOY_USER` | SSH user | `clawdis` or your username |
| `DEPLOY_PATH` | App directory (optional) | `/opt/clawdis/app` |

#### 4. Create Environment (Optional but Recommended)
For production deployments, create a protected environment:

1. Go to Settings → Environments
2. Click "New environment"
3. Name it `production`
4. Add protection rules:
   - Required reviewers
   - Deployment branches (main only)
5. Add environment-specific secrets if needed

### Usage

#### Manual Deployment
1. Go to Actions → Deploy to VM
2. Click "Run workflow"
3. Select environment (production/staging/development)
4. Choose "Only restart service" if you just need a restart
5. Click "Run workflow"

#### Restart Only
Use the "restart_only" option to restart without updating code:
- Useful for configuration changes
- Faster than full deployment
- No git pull or rebuild

### Troubleshooting

If deployment fails:

```bash
# SSH into your VM manually
ssh user@your-vm-ip

# Check service status
sudo systemctl status clawdis-gateway.service

# View logs
sudo journalctl -u clawdis-gateway.service -n 50
```

Common issues:
- **Permission denied**: Ensure SSH key is added to `authorized_keys`
- **sudo requires password**: Configure passwordless sudo for the deploy user
- **Service won't start**: Check logs for configuration errors

## Workflow 3: Deploy via Docker

### What It Does
- SSHs into your VM
- Pulls the latest Docker image from GHCR
- Stops the existing container
- Starts a new container with updated image
- Verifies container health

### Setup

#### 1. Install Docker on VM
```bash
# On your VM
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group to take effect
```

#### 2. Configure GitHub Secrets
Add to Settings → Secrets and variables → Actions:

| Secret Name | Value | Required |
|-------------|-------|----------|
| `DEPLOY_SSH_KEY` | SSH private key | ✅ |
| `DEPLOY_HOST` | VM hostname/IP | ✅ |
| `DEPLOY_USER` | SSH user | ✅ |
| `CLAWDIS_GATEWAY_TOKEN` | Gateway auth token | ⚠️ Recommended |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | ❌ Optional |
| `DISCORD_BOT_TOKEN` | Discord bot token | ❌ Optional |

Generate a secure gateway token:
```bash
openssl rand -hex 32
```

#### 3. First-Time Setup on VM

SSH into your VM and set up WhatsApp credentials:

```bash
# Create volumes
docker volume create clawdis-config
docker volume create clawdis-workspace

# Run temporary container for WhatsApp login
docker run -it --rm \
  -v clawdis-config:/home/clawdis/.clawdis \
  ghcr.io/OWNER/REPO:latest \
  pnpm clawdis login

# Scan QR code with WhatsApp
```

Credentials are now persisted in the `clawdis-config` volume.

### Usage

#### Deploy Latest Image
1. Go to Actions → Deploy via Docker
2. Click "Run workflow"
3. Select environment
4. Leave image_tag as `latest` (or specify a version)
5. Click "Run workflow"

#### Deploy Specific Version
Use the `image_tag` input to deploy a specific version:
- `latest` - Most recent main build
- `v2.0.0` - Specific release
- `main-abc1234` - Specific commit

### Monitoring

After deployment, check container status:

```bash
# SSH into VM
ssh user@your-vm-ip

# View running containers
docker ps

# View logs
docker logs -f clawdis-gateway

# Check health
docker inspect --format='{{.State.Health.Status}}' clawdis-gateway
```

## Multi-Environment Setup

### Create Multiple Environments

For production, staging, and development deployments:

1. **Create environments** in Settings → Environments:
   - `production`
   - `staging`
   - `development`

2. **Add environment-specific secrets**:
   - Different VMs per environment
   - Different tokens/credentials
   - Different configurations

3. **Configure protection rules**:
   - Production: Required reviewers, main branch only
   - Staging: Auto-deploy from main
   - Development: No restrictions

### Example: Multi-VM Setup

| Environment | VM | Config |
|-------------|----|----|
| Production | `prod.example.com` | Protected, manual approval |
| Staging | `staging.example.com` | Auto-deploy on main push |
| Development | `dev.example.com` | Deploy anytime, any branch |

### Automatic Deployments

Modify workflows to auto-deploy on push:

```yaml
# .github/workflows/auto-deploy-staging.yml
name: Auto Deploy to Staging

on:
  push:
    branches:
      - main

jobs:
  deploy:
    uses: ./.github/workflows/deploy-docker.yml
    with:
      environment: staging
      image_tag: latest
    secrets: inherit
```

## Advanced: Custom Deployment Script

For complex deployments, create a custom script:

```bash
# scripts/deploy-custom.sh
#!/bin/bash
set -e

echo "🚀 Custom deployment starting..."

# Pre-deployment tasks
echo "Running pre-deployment checks..."
./scripts/health-check.sh

# Deploy
echo "Deploying application..."
pnpm build
sudo systemctl restart clawdis-gateway

# Post-deployment tasks
echo "Running smoke tests..."
./scripts/smoke-test.sh

echo "✅ Deployment complete!"
```

Reference in workflow:
```yaml
- name: Run custom deploy
  run: |
    ssh $DEPLOY_USER@$DEPLOY_HOST 'bash -s' < scripts/deploy-custom.sh
```

## Image Registry Alternatives

### Use Docker Hub Instead of GHCR

Edit `.github/workflows/docker-publish.yml`:

```yaml
env:
  REGISTRY: docker.io
  IMAGE_NAME: username/clawdis

# ...

- name: Log in to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}
```

### Use Private Registry

```yaml
env:
  REGISTRY: registry.example.com
  IMAGE_NAME: clawdis/gateway

# ...

- name: Log in to private registry
  uses: docker/login-action@v3
  with:
    registry: ${{ env.REGISTRY }}
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

## Security Best Practices

### 1. Protect Secrets
- Never commit secrets to repository
- Use GitHub Secrets for sensitive data
- Rotate SSH keys regularly
- Use different tokens per environment

### 2. Limit SSH Access
```bash
# On VM, restrict SSH key to specific commands (optional)
# ~/.ssh/authorized_keys
command="/usr/local/bin/deploy-clawdis.sh" ssh-ed25519 AAAA...
```

### 3. Use Protected Branches
- Require PR reviews for main
- Enable branch protection rules
- Require status checks to pass

### 4. Enable 2FA
- Enable 2FA on GitHub account
- Use deploy keys instead of personal tokens when possible

### 5. Audit Deployments
- Review Actions logs regularly
- Set up notifications for deployment failures
- Monitor VM logs after deployments

## Monitoring & Notifications

### Slack Notifications

Add to workflow:
```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
    payload: |
      {
        "text": "Deployment ${{ job.status }}: ${{ github.repository }}"
      }
```

### Email Notifications

GitHub Actions sends email on failure by default. Customize in:
- Settings → Notifications → Actions

### Discord Notifications

```yaml
- name: Notify Discord
  if: always()
  uses: sarisia/actions-status-discord@v1
  with:
    webhook: ${{ secrets.DISCORD_WEBHOOK }}
    status: ${{ job.status }}
```

## Rollback Procedures

### Docker Rollback
```bash
# SSH into VM
ssh user@your-vm-ip

# Stop current container
docker stop clawdis-gateway
docker rm clawdis-gateway

# Run previous version
docker run -d \
  --name clawdis-gateway \
  --restart unless-stopped \
  -v clawdis-config:/home/clawdis/.clawdis \
  -v clawdis-workspace:/home/clawdis/clawd \
  ghcr.io/OWNER/REPO:v1.9.0  # Previous version
```

### Systemd Rollback
```bash
# SSH into VM
cd /opt/clawdis/app

# Check previous commits
git log --oneline -n 10

# Rollback to previous commit
git reset --hard abc1234

# Rebuild and restart
pnpm install
pnpm build
sudo systemctl restart clawdis-gateway
```

## Troubleshooting

### Workflow Fails: "Permission denied"
- Check SSH key is correct in secrets
- Verify key is added to VM's `~/.ssh/authorized_keys`
- Ensure correct file permissions (600 for private key, 644 for authorized_keys)

### Workflow Fails: "Image not found"
- Wait for Docker build workflow to complete
- Check image exists: `docker pull ghcr.io/OWNER/REPO:TAG`
- Verify GITHUB_TOKEN has packages:write permission

### Container Won't Start
- Check logs: `docker logs clawdis-gateway`
- Verify secrets are set correctly
- Ensure WhatsApp credentials are in volume

### Service Health Check Fails
- Wait longer for service to start (increase sleep time)
- Check if ports are correctly exposed
- Verify firewall isn't blocking ports

## Cost Optimization

### Reduce Build Time
- Use cache: Already configured in workflows
- Build only on main pushes, not PRs
- Use smaller base images

### Reduce Registry Storage
- Set up image retention policy:
  - Settings → Packages → Manage versions → Cleanup policy
- Keep only last 10 versions
- Delete untagged images

### Optimize Runner Usage
- Use `if` conditions to skip unnecessary steps
- Run jobs in parallel where possible
- Use self-hosted runners for frequent deployments

## Related Documentation

- [VM Deployment Guide](vm-deployment.md)
- [Docker Deployment Guide](docker-deployment.md)
- [Configuration Reference](configuration.md)
- [Security Guidelines](security.md)

## Quick Reference

### Deploy to Production (VM)
```
Actions → Deploy to VM → Run workflow → production
```

### Deploy to Production (Docker)
```
Actions → Deploy via Docker → Run workflow → production → latest
```

### Build New Image
```
git tag v2.0.1
git push origin v2.0.1
# Wait for Docker Build & Publish workflow
```

### Emergency Restart
```
Actions → Deploy to VM → restart_only: true
```
