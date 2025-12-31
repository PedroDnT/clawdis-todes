#!/usr/bin/env bash
set -euo pipefail

# Clawdis VM Deployment Script
# Usage: sudo bash vm-deploy.sh [--user USER] [--install-dir DIR]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
CLAWDIS_USER="${CLAWDIS_USER:-clawdis}"
INSTALL_DIR="${INSTALL_DIR:-/opt/clawdis}"
NODE_VERSION="22"
PNPM_VERSION="10.23.0"
GATEWAY_PORT="18789"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --user)
      CLAWDIS_USER="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --user USER          Service user (default: clawdis)"
      echo "  --install-dir DIR    Installation directory (default: /opt/clawdis)"
      echo "  --help               Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
  fi
}

install_dependencies() {
  log_info "Installing system dependencies..."

  if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y curl git build-essential lsof
  elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y curl git gcc-c++ make lsof
  else
    log_error "Unsupported package manager. Please install curl, git, and build-essential manually."
    exit 1
  fi
}

create_user() {
  if id "$CLAWDIS_USER" &>/dev/null; then
    log_warn "User $CLAWDIS_USER already exists, skipping creation"
  else
    log_info "Creating service user: $CLAWDIS_USER"
    useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$CLAWDIS_USER"
  fi
}

install_node() {
  log_info "Installing Node.js $NODE_VERSION for $CLAWDIS_USER..."

  # Install nvm for the service user
  sudo -u "$CLAWDIS_USER" bash <<EOF
set -e
export HOME="$INSTALL_DIR"

# Check if nvm already installed
if [ ! -d "\$HOME/.nvm" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
fi

# Load nvm
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

# Install and use Node
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
EOF
}

install_pnpm() {
  log_info "Installing pnpm for $CLAWDIS_USER..."

  sudo -u "$CLAWDIS_USER" bash <<EOF
set -e
export HOME="$INSTALL_DIR"

# Load nvm
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

# Install pnpm if not present
if ! command -v pnpm &> /dev/null; then
  curl -fsSL https://get.pnpm.io/install.sh | sh -
fi
EOF
}

clone_and_build() {
  log_info "Cloning and building Clawdis..."

  sudo -u "$CLAWDIS_USER" bash <<EOF
set -e
export HOME="$INSTALL_DIR"

# Load nvm and pnpm
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
export PNPM_HOME="\$HOME/.local/share/pnpm"
export PATH="\$PNPM_HOME:\$PATH"

# Clone if not exists
if [ ! -d "\$HOME/app" ]; then
  git clone https://github.com/steipete/clawdis.git "\$HOME/app"
else
  echo "App directory exists, pulling latest..."
  cd "\$HOME/app"
  git pull origin main
fi

cd "\$HOME/app"

# Install dependencies and build
pnpm install
pnpm build
pnpm ui:build

# Link globally
pnpm link --global
EOF
}

create_config() {
  log_info "Creating initial configuration..."

  sudo -u "$CLAWDIS_USER" bash <<EOF
set -e
export HOME="$INSTALL_DIR"

mkdir -p "\$HOME/.clawdis"

if [ ! -f "\$HOME/.clawdis/clawdis.json" ]; then
  cat > "\$HOME/.clawdis/clawdis.json" <<'CONFIG'
{
  "routing": {
    "allowFrom": []
  },
  "gateway": {
    "port": 18789,
    "bindPolicy": "loopback"
  },
  "agent": {
    "workspace": "$INSTALL_DIR/clawd"
  }
}
CONFIG
  echo "Created config at \$HOME/.clawdis/clawdis.json"
else
  echo "Config already exists, skipping"
fi
EOF
}

create_systemd_service() {
  log_info "Creating systemd service..."

  # Get Node.js path
  NODE_PATH=$(sudo -u "$CLAWDIS_USER" bash <<EOF
export HOME="$INSTALL_DIR"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
which node | xargs dirname
EOF
)

  # Get pnpm path
  PNPM_BIN="$INSTALL_DIR/.local/share/pnpm"

  cat > /etc/systemd/system/clawdis-gateway.service <<EOF
[Unit]
Description=Clawdis Gateway - Personal AI Assistant
Documentation=https://github.com/steipete/clawdis
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CLAWDIS_USER
Group=$CLAWDIS_USER
WorkingDirectory=$INSTALL_DIR/app

# Use the globally-linked clawdis binary
ExecStart=$PNPM_BIN/clawdis gateway --port $GATEWAY_PORT

# Restart policy
Restart=on-failure
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=300

# Environment
Environment="NODE_ENV=production"
Environment="PATH=$NODE_PATH:$PNPM_BIN:/usr/local/bin:/usr/bin:/bin"

# Security hardening
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$INSTALL_DIR

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=clawdis-gateway

# Resource limits
MemoryMax=1G
TasksMax=256

[Install]
WantedBy=multi-user.target
EOF

  log_info "Reloading systemd daemon..."
  systemctl daemon-reload
  systemctl enable clawdis-gateway.service
}

print_next_steps() {
  log_info "Installation complete!"
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Clawdis Gateway has been installed successfully!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Next steps:"
  echo ""
  echo "1. Configure your settings:"
  echo -e "   ${YELLOW}sudo -u $CLAWDIS_USER nano $INSTALL_DIR/.clawdis/clawdis.json${NC}"
  echo ""
  echo "2. Link WhatsApp (requires interactive terminal):"
  echo -e "   ${YELLOW}sudo -u $CLAWDIS_USER -i${NC}"
  echo -e "   ${YELLOW}cd $INSTALL_DIR/app${NC}"
  echo -e "   ${YELLOW}pnpm clawdis login${NC}"
  echo ""
  echo "3. Start the gateway service:"
  echo -e "   ${YELLOW}sudo systemctl start clawdis-gateway.service${NC}"
  echo ""
  echo "4. Check service status:"
  echo -e "   ${YELLOW}sudo systemctl status clawdis-gateway.service${NC}"
  echo ""
  echo "5. View logs:"
  echo -e "   ${YELLOW}sudo journalctl -u clawdis-gateway.service -f${NC}"
  echo ""
  echo "Documentation:"
  echo "  - Full guide: docs/vm-deployment.md"
  echo "  - Gateway: docs/gateway.md"
  echo "  - Configuration: docs/configuration.md"
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# Main execution
main() {
  log_info "Starting Clawdis VM deployment..."
  log_info "User: $CLAWDIS_USER"
  log_info "Install directory: $INSTALL_DIR"
  echo ""

  check_root
  install_dependencies
  create_user
  install_node
  install_pnpm
  clone_and_build
  create_config
  create_systemd_service

  print_next_steps
}

main "$@"
