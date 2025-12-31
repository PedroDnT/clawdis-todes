# Clawdis Gateway Dockerfile
# Multi-stage build for smaller final image

# Build stage
FROM node:22-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    python3 \
    make \
    g++

WORKDIR /build

# Copy package files
COPY package.json pnpm-lock.yaml ./
COPY pnpm-workspace.yaml ./

# Install pnpm
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build TypeScript and UI
RUN pnpm build && pnpm ui:build

# Production stage
FROM node:22-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates

# Create app user
RUN addgroup -g 1000 clawdis && \
    adduser -D -u 1000 -G clawdis clawdis

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Copy built application from builder
COPY --from=builder --chown=clawdis:clawdis /build/package.json ./
COPY --from=builder --chown=clawdis:clawdis /build/pnpm-lock.yaml ./
COPY --from=builder --chown=clawdis:clawdis /build/dist ./dist
COPY --from=builder --chown=clawdis:clawdis /build/ui/dist ./ui/dist
COPY --from=builder --chown=clawdis:clawdis /build/docs ./docs
COPY --from=builder --chown=clawdis:clawdis /build/skills ./skills

# Install production dependencies only
RUN pnpm install --prod --frozen-lockfile

# Switch to app user
USER clawdis

# Create data directories
RUN mkdir -p /home/clawdis/.clawdis/credentials && \
    mkdir -p /home/clawdis/.clawdis/sessions && \
    mkdir -p /home/clawdis/clawd

# Expose ports
EXPOSE 18789 18790 18793

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:18789', (r) => process.exit(r.statusCode === 426 ? 0 : 1))"

# Environment variables
ENV NODE_ENV=production \
    CLAWDIS_HOME=/home/clawdis/.clawdis

# Start gateway
CMD ["node", "dist/index.js", "gateway", "--port", "18789"]
