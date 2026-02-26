FROM node:20-slim

# prevent apt-get from asking questions
ENV DEBIAN_FRONTEND=noninteractive

# install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git gnupg build-essential libssl-dev pkg-config \
    gh python3 procps chromium libnss3 libgbm1 libasound2 fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# install global clis
RUN npm install -g bun serve opencode-ai@latest agent-browser opencode-hive@latest

# install uv (python manager) from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# set workdir
WORKDIR /app/projects

# copy the startup script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# environment variables for binary paths
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium

ENTRYPOINT ["entrypoint.sh"]
