#!/bin/bash
set -e

# update path for bun and local tools
export PATH="/root/.local/bin:/root/.bun/bin:$PATH"

# ensure directories exist
mkdir -p /root/.config/opencode/skills /app/projects /shared/bin

# here you can run your node script to generate the config files
# (insert your long node -e code here or call a separate js file)

# start opencode in background
cd /app/projects && opencode serve --hostname 127.0.0.1 &

# start the media viewer
serve /app/projects -p $MEDIA_PORT --cors --no-clipboard &

# run openchamber as the main process
OPENCODE_PORT=4096 OPENCODE_SKIP_START=true exec openchamber --port 4097
