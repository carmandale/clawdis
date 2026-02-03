#!/bin/sh
# Railway init script - configure Chip agent for Railway deployment
# 
# Architecture (from openclaw-flow.png):
# - Local Mac: TUI via Ghostty
# - Railway: Telegram (iPhone), Discord (iPad), Webchat
# - Both share chipbot workspace via git sync

set -e

# Ensure directories exist (Railway volume may be empty on first deploy)
mkdir -p /data/.clawdbot/workspace

CONFIG_FILE="/data/.clawdbot/openclaw.json"

# Clone workspace if not present, or pull updates
if [ -d "/data/.clawdbot/workspace/chipbot/.git" ]; then
  echo "Pulling latest workspace changes..."
  (cd /data/.clawdbot/workspace/chipbot && git pull --ff-only) || true
else
  echo "Cloning workspace..."
  mkdir -p /data/.clawdbot/workspace
  git clone https://github.com/carmandale/chipbot.git /data/.clawdbot/workspace/chipbot || {
    echo "WARNING: Failed to clone workspace, continuing anyway"
  }
fi

# Configure the gateway for Railway BEFORE running doctor
echo "Configuring Railway gateway settings..."
node -e "
  const fs = require('fs');
  const configPath = '$CONFIG_FILE';
  
  let config = {};
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (e) {
    console.log('Creating new config file');
  }

  // Gateway configuration
  if (!config.gateway) config.gateway = {};
  
  // CRITICAL: Bind to 0.0.0.0 for external access
  config.gateway.bind = 'lan';
  
  // Trust Railway's internal proxy (100.64.0.0/10 range)
  // This allows proper client IP detection and local-like treatment
  config.gateway.trustedProxies = ['100.64.0.0/10', '10.0.0.0/8'];
  
  // Enable Control UI for webchat
  if (!config.gateway.controlUi) config.gateway.controlUi = {};
  config.gateway.controlUi.enabled = true;
  
  // Set gateway auth token from env var (required for node connections)
  const gatewayToken = process.env.OPENCLAW_GATEWAY_TOKEN;
  if (gatewayToken) {
    if (!config.gateway.auth) config.gateway.auth = {};
    config.gateway.auth.token = gatewayToken;
    console.log('Gateway auth token configured from OPENCLAW_GATEWAY_TOKEN');
  } else {
    console.log('WARNING: OPENCLAW_GATEWAY_TOKEN not set - node connections will fail');
  }
  
  // Agents configuration
  if (!config.agents) {
    config.agents = { defaults: {}, list: [] };
  }
  
  // Set workspace
  config.agents.defaults = config.agents.defaults || {};
  config.agents.defaults.workspace = '/data/.clawdbot/workspace/chipbot';
  
  // Configure session storage in workspace for git syncing
  if (!config.session) config.session = {};
  config.session.store = '/data/.clawdbot/workspace/chipbot/sessions/railway/{agentId}/sessions.json';
  config.session.dmScope = 'per-channel-peer';
  
  // Add Chip agent if not present
  if (!config.agents.list) config.agents.list = [];
  const hasChip = config.agents.list.some(a => a.id === 'main');
  if (!hasChip) {
    config.agents.list.push({
      id: 'main',
      identity: {
        name: 'Chip',
        emoji: '🐿️'
      }
    });
  }

  // Channels configuration - enable Telegram and Discord
  if (!config.channels) config.channels = {};
  
  // Telegram configuration (token from OPENCLAW_TELEGRAM_BOT_TOKEN env var)
  const telegramToken = process.env.OPENCLAW_TELEGRAM_BOT_TOKEN;
  if (telegramToken) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.enabled = true;
    config.channels.telegram.botToken = telegramToken;
    // Allow DMs without pairing - open policy requires allowFrom: ["*"]
    config.channels.telegram.dmPolicy = 'open';
    config.channels.telegram.allowFrom = ['*'];
    console.log('Telegram channel configured (dmPolicy=open, allowFrom=*)');
  } else {
    console.log('WARNING: OPENCLAW_TELEGRAM_BOT_TOKEN not set - Telegram disabled');
  }
  
  // Discord configuration (token from OPENCLAW_DISCORD_TOKEN env var)
  const discordToken = process.env.OPENCLAW_DISCORD_TOKEN;
  if (discordToken) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.enabled = true;
    config.channels.discord.token = discordToken;  // Discord uses 'token' not 'botToken'
    delete config.channels.discord.botToken;  // Remove invalid key if present from old config
    // Configure DM settings - allow without pairing, requires allowFrom: ["*"]
    config.channels.discord.dm = config.channels.discord.dm || {};
    config.channels.discord.dm.enabled = true;
    config.channels.discord.dm.policy = 'open';
    config.channels.discord.dm.allowFrom = ['*'];
    console.log('Discord channel configured (dm.policy=open, allowFrom=*)');
  } else {
    console.log('WARNING: OPENCLAW_DISCORD_TOKEN not set - Discord disabled');
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log('Railway gateway configuration complete');
  console.log('Config summary:');
  console.log('  - gateway.bind: ' + config.gateway.bind);
  console.log('  - gateway.trustedProxies: ' + JSON.stringify(config.gateway.trustedProxies));
  console.log('  - channels.telegram.enabled: ' + (config.channels.telegram?.enabled || false));
  console.log('  - channels.discord.enabled: ' + (config.channels.discord?.enabled || false));
"

# Run doctor after config is set up (use absolute path - WORKDIR is /app)
echo "Running doctor..."
node /app/dist/index.js doctor --fix || true

# Start gateway with Railway-compatible settings
# --bind lan resolves to 0.0.0.0 for external access
# OPENCLAW_GATEWAY_TOKEN must be set for non-loopback binding
exec node /app/dist/index.js gateway run \
  --allow-unconfigured \
  --port "${PORT:-18789}" \
  --bind lan
