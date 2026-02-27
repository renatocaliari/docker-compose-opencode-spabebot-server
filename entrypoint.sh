#!/bin/bash
set -e

echo "starting environment configuration..."

export PATH="/root/.local/bin:/root/.bun/bin:$PATH"
export BUN_PTY_LIB="/root/.bun/install/global/node_modules/bun-pty/rust-pty/target/release/librust_pty_arm64.so"

echo "configuring arm64 library..."
ln -sf "$BUN_PTY_LIB" "/root/.bun/install/global/node_modules/bun-pty/rust-pty/target/release/librust_pty.so"

if [ ! -f "$BUN_PTY_LIB" ]; then
  echo "error. arm64 library not found at $BUN_PTY_LIB"
  exit 1
fi

chmod +x "$BUN_PTY_LIB"
export SHELL=/bin/bash

echo "installing qwencode auth plugin..."
mkdir -p /root/.opencode
cd /root/.opencode
npm install opencode-qwencode-auth --no-save || true

echo "configuring github cli credentials..."
gh auth setup-git || true

echo "installing agent-browser skills via npx..."
npx --yes skills@latest add https://github.com/vercel-labs/agent-browser --yes --global || echo "warning. base skill failed."
npx --yes skills@latest add https://github.com/vercel-labs/agent-browser --skill dogfood --yes --global --agents opencode || echo "warning. dogfood skill failed."

mkdir -p /root/.config/opencode/skills
cp /root/.agents/skills/*.md /root/.config/opencode/skills/ 2>/dev/null || true

echo "generating configuration and agent files..."
node -e '
  const fs = require("fs");

  const opencodePath = "/root/.config/opencode/opencode.json";
  let c = {};
  if (fs.existsSync(opencodePath)) {
    try { c = JSON.parse(fs.readFileSync(opencodePath, "utf8")); } catch(e) {}
  }

  if ("" in c) delete c[""];

  c.lsp = c.lsp || {};
  c.lsp["basedpyright"] = {
    command: ["uvx", "--from", "basedpyright", "basedpyright-langserver", "--stdio"],
    extensions: [".py", ".pyi"]
  };
  c.lsp["htpy-lsp"] = {
    command: ["uvx", "--from", "htpy-lsp", "htpy-lsp", "--stdio"],
    extensions: [".py"]
  };

  const requiredPlugins = [
    "@plannotator/opencode@latest",
    "opencode-hive",
    "opencode-synced",
    "opencode-qwencode-auth"
  ];
  c.plugin = c.plugin || [];
  for (const p of requiredPlugins) {
    if (!c.plugin.includes(p)) c.plugin.push(p);
  }

  const bigModel = process.env.PROVIDER_MODEL_BIG || "zai-coding-plan/glm-4.7";
  const smallModel = process.env.PROVIDER_MODEL_SMALL || "zai-coding-plan/glm-4.7-flash";

  let providerName = "zai-coding-plan";
  if (bigModel.includes("/")) {
    providerName = bigModel.split("/")[0];
  }

  c.provider = c.provider || {};
  c.provider[providerName] = c.provider[providerName] || {};
  c.provider[providerName].options = c.provider[providerName].options || {};
  c.provider[providerName].options.apiKey = process.env.PROVIDER_MODEL_API_KEY || "chave_vazia";

  if (process.env.PROVIDER_MODEL_BASE_URL) {
    c.provider[providerName].options.baseURL = process.env.PROVIDER_MODEL_BASE_URL;
  }

  c.model = bigModel;
  c.small_model = smallModel;

  if (c.mcp && c.mcp["chrome-devtools"]) delete c.mcp["chrome-devtools"];

  fs.writeFileSync(opencodePath, JSON.stringify(c, null, 2));

  const hivePath = "/root/.config/opencode/agent_hive.json";
  const hiveConfig = {
    "$schema": "https://raw.githubusercontent.com/tctinh/agent-hive/main/packages/opencode-hive/schema/agent_hive.schema.json",
    "agentMode": "unified",
    "disableSkills": [],
    "disableMcps": [],
    "agents": {
      "hive-master": {
        "model": bigModel,
        "temperature": 0.5,
        "autoLoadSkills": ["reviewing-plans-with-plannotator"]
      },
      "forager-worker": {
        "model": bigModel,
        "temperature": 0.5
      },
      "scout-researcher": {
        "model": smallModel,
        "temperature": 0.3
      },
      "hygienic-reviews": {
        "model": bigModel,
        "temperature": 0.3
      }
    }
  };
  fs.writeFileSync(hivePath, JSON.stringify(hiveConfig, null, 2));

  const host = process.env.PLANNOTATOR_PUBLIC_HOST || "localhost";
  const port = process.env.PLANNOTATOR_PORT || "19432";
  const serverHost = process.env.SERVER_PUBLIC_HOST || "localhost";
  const mediaPort = process.env.MEDIA_PORT || "5000";

  const skillMd = [
    "---",
    "name: reviewing-plans-with-plannotator",
    "description: >",
    "  Replaces the default plan approval gate with Plannotator visual review.",
    "  Use when hive-master needs to review implementation plans, requires visual",
    "  plan approval, or user mentions Plannotator. Only hive-master should use",
    "  this skill.",
    "---",
    "# Reviewing Plans with Plannotator",
    "",
    "## Workflow",
    "",
    "1. Read plan: `cat .hive/features/<feature-name>/plan.md`",
    "",
    "2. Submit for visual review:",
    "   Call `submit_plan({ \"plan\": \"<contents>\", \"title\": \"<name>\" })`",
    "   Show the plan review URL to the user: `http://" + host + ":" + port + "`",
    "",
    "3. Wait for approval:",
    "   - If approved: proceed to executing-plans.",
    "   - If changes_requested: update plan.md and repeat."
  ].join(String.fromCharCode(10));
  fs.mkdirSync("/root/.config/opencode/skills/reviewing-plans-with-plannotator", { recursive: true });
  fs.writeFileSync("/root/.config/opencode/skills/reviewing-plans-with-plannotator/SKILL.md", skillMd);

  const agentsMd = [
    "# Global Agent Instructions",
    "",
    "## Traceability and Plan Review",
    "You are running inside Opencode. To make your tasks visible, you MUST call \"submit_plan\" before delegating to subagents or implementing any plan.",
    "Show the plan review URL to the user: `http://" + host + ":" + port + "`",
    "",
    "## Project Management",
    "ALL projects MUST be located under /app/projects/. Never create or manage",
    "projects in any other directory (not /projects, not /tmp, not /root, etc.).",
    "When asked to work on a project, always navigate to /app/projects/<project-name>.",
    "When asked to create a new project, always create it under /app/projects/.",
    "List available projects with: ls /app/projects/",
    "",
    "## Agent Coordination (agent-hive)",
    "Always use the hive-master agent to coordinate tasks.",
    "The hive-master delegates to specialist agents via background_task.",
    "",
    "## Planning and Approval",
    "Before implementing any non-trivial feature, always call submit_plan",
    "so the user can review and approve the plan via Plannotator UI.",
    "You must explicitly show this url to the user to approve the plan: http://" + host + ":" + port,
    "Instruct the user to open the url and approve it there.",
    "Never start writing code without an approved plan.",
    "Use a high-reasoning LLM for planning tasks.",
    "",
    "## Living Documentation (Spec-Driven)",
    "This environment uses a Living Documentation approach instead of rigid folders.",
    "1. Always look for a docs/current_system.md or a similar central spec file.",
    "2. When you implement a feature, change business logic, or delete code, YOU MUST UPDATE the central specification to reflect the new reality.",
    "3. Do not leave deprecated rules in the documentation. The spec must be a single source of truth for the CURRENT system state.",
    "4. Treat documentation updates as part of the coding task, not an afterthought.",
    "",
    "## Testing",
    "Every feature implementation must include tests.",
    "Tests must be written before or alongside implementation, never as an afterthought.",
    "Never mark a task as complete if its tests are missing or failing.",
    "",
    "## Media and File Navigation (Dogfood Skill)",
    "when you use the dogfood skill to execute commands or manipulate files,",
    "you must inform the user that they can navigate all project files and watch videos directly via this url:",
    "`http://" + serverHost + ":" + mediaPort + "`"
  ].join(String.fromCharCode(10));
  fs.writeFileSync("/root/.config/opencode/AGENTS.md", agentsMd);

  const shellScript = [
    "#!/bin/sh",
    "URL=$(echo \"$1\" | sed \"s/localhost/" + host + "/g\")",
    "echo \"\"",
    "echo \">>> PLANNOTATOR ready for review: $URL\"",
    "echo \"\""
  ].join("\n");
  fs.writeFileSync("/usr/local/bin/plannotator-open-url", shellScript);
  fs.chmodSync("/usr/local/bin/plannotator-open-url", 0o755);

  const opencodeSyncedConfig = {
    "$schema": "https://raw.githubusercontent.com/iHildy/opencode-synced/main/schemas/config.json",
    "repo": {
      "owner": "renatocaliari",
      "name": "my-opencode-config"
    },
    "includeSecrets": true,
    "includeMcpSecrets": true,
    "includeSessions": false,
    "includePromptStash": false,
    "includeModelFavorites": true,
    "extraConfigPaths": [
      "~/.config/opencode/skills"
    ],
    "extraSecretPaths": []
  };
  fs.writeFileSync("/root/.config/opencode/opencode-synced.jsonc", JSON.stringify(opencodeSyncedConfig, null, 2));
'

echo "installing plannotator..."
curl -fsSL https://plannotator.ai/install.sh | bash || echo "warning. plannotator install.sh failed."

echo "verifying cli and lsp installations..."
opencode --version && echo "opencode ok."
uv tool list | grep -E "(basedpyright|htpy-lsp)" && echo "lsps ok."

mkdir -p /shared/bin
cp $(which opencode) /shared/bin/opencode

echo "================================================================"
echo " stack ready"
echo "================================================================"

echo "starting opencode server in background..."
cd /app/projects
opencode serve --hostname 127.0.0.1 &
sleep 2

ln -sfn /app/projects /root/projects

echo "starting media file server..."
serve /app/projects -p 5000 --cors --no-clipboard &

echo "starting openchamber..."
OPENCODE_PORT=4096 OPENCODE_SKIP_START=true exec openchamber --port 4097
