FROM node:20-slim

ENV DEBIAN_FRONTEND=noninteractive

# install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    build-essential \
    libssl-dev \
    pkg-config \
    gh \
    python3 \
    procps \
    chromium \
    libnss3 \
    libgbm1 \
    libasound2 \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# install cloudflared (arm64)
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# install npm, bun and global packages
RUN npm install -g bun \
    && npm install -g node-gyp \
    && npm install -g opencode-ai@latest \
    && bun add -g @openchamber/web \
    && bun add -g bun-pty \
    && npm install -g agent-browser \
    && npm install -g opencode-hive@latest \
    && npm install -g serve

# configure agent-browser
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
RUN npm_config_yes=true agent-browser install || true

# install uv (python manager) and lsps
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
RUN uv tool install basedpyright \
    && uv tool install htpy-lsp

# create directories and set permissions
RUN mkdir -p /root/.config/opencode/skills /root/.opencode /app/projects /shared/bin

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PATH="/root/.local/bin:/root/.bun/bin:$PATH"

WORKDIR /app/projects

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
