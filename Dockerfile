FROM node:22-slim

LABEL org.opencontainers.image.source="https://github.com/Wechat-ggGitHub/wechat-claude-code"
LABEL org.opencontainers.image.description="WeChat Claude Code Bridge - cloud deployment"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI globally (deprecated npm method but works in containers)
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app

# Install deps only (skip postinstall build until source is copied)
COPY package.json package-lock.json tsconfig.json ./
RUN npm install --ignore-scripts

# Copy source and build
COPY src/ ./src/
RUN npm run build

# Remove devDependencies after build
RUN npm prune --production

# Runtime assets
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /root/.wechat-claude-code/accounts /root/.wechat-claude-code/logs

ENV NODE_ENV=production
ENV HOME=/root
ENV CLAUDE_CODE_CI_MODE=true
ENV CLAUDE_CODE_QUIET=true
ENV HEALTH_PORT=7860

EXPOSE 7860

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
