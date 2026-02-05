#!/bin/sh
# Railway init script - configure Chip agent for Railway deployment
# 
# Architecture (from openclaw-flow.png):
# - Local Mac: TUI via Ghostty
# - Railway: Telegram (iPhone), Discord (iPad), Webchat
# - Both share chipbot workspace via git sync
#
# SECURITY HARDENING (2026-02-04):
# - DM policy: pairing (not open) - requires approval before commands work
# - Allowlists: specific user IDs only (not ["*"])
# - Gateway token: read from env only, not written to config
# - Sessions: stored outside git workspace to prevent accidental exposure
# - Elevated tools: disabled by default

set -e

# CRITICAL: Set state/config paths BEFORE any OpenClaw commands
# This ensures the gateway reads config from the persistent volume
export OPENCLAW_STATE_DIR="/data/.clawdbot"
export OPENCLAW_CONFIG_PATH="/data/.clawdbot/openclaw.json"

# SECURITY: Require gateway token for internet-facing deployment
if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  echo "ERROR: OPENCLAW_GATEWAY_TOKEN not set - refusing to start internet-facing gateway without auth"
  exit 1
fi

# Ensure directories exist (Railway volume may be empty on first deploy)
mkdir -p /data/.clawdbot/workspace
mkdir -p /data/.clawdbot/sessions
# Create ephemeral session directory for stability (fast I/O)
mkdir -p /tmp/openclaw-sessions

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

  // ============================================
  // OWNER IDS - Update these if you change accounts
  // ============================================
  const OWNER_TELEGRAM_ID = process.env.OWNER_TELEGRAM_ID || '6980882002';
  const OWNER_DISCORD_ID = process.env.OWNER_DISCORD_ID || '244850829801029632';

  // Gateway configuration
  if (!config.gateway) config.gateway = {};
  
  // CRITICAL: Bind to 0.0.0.0 for external access
  config.gateway.bind = 'lan';
  
  // trustedProxies - Railway's internal proxy IPs (100.64.0.x range)
  // CIDR is not supported, so we list individual IPs
  // This enables proper client IP detection and local-like treatment
  config.gateway.trustedProxies = [
    '100.64.0.1', '100.64.0.2', '100.64.0.3', '100.64.0.4',
    '100.64.0.5', '100.64.0.6', '100.64.0.7', '100.64.0.8',
    '100.64.0.9', '100.64.0.10', '100.64.0.11', '100.64.0.12',
    '100.64.0.13', '100.64.0.14', '100.64.0.15', '100.64.0.16'
  ];
  
  // Enable Control UI for webchat
  if (!config.gateway.controlUi) config.gateway.controlUi = {};
  config.gateway.controlUi.enabled = true;
  
  // SECURITY: Do NOT write gateway token to config file
  // The gateway reads OPENCLAW_GATEWAY_TOKEN from environment directly
  // This prevents token exposure if config file is accidentally leaked
  if (config.gateway.auth?.token) {
    delete config.gateway.auth.token;
    console.log('Removed gateway token from config (using env var instead)');
  }
  
  // Agents configuration
  if (!config.agents) {
    config.agents = { defaults: {}, list: [] };
  }
  
  // Set workspace
  config.agents.defaults = config.agents.defaults || {};
  config.agents.defaults.workspace = '/data/.clawdbot/workspace/chipbot';
  
  // STABILITY: Store sessions on fast ephemeral disk to avoid event loop blocking
  // Railway persistent volumes have higher I/O latency which can cause Discord
  // gateway to miss heartbeats and enter reconnection loops.
  // Trade-off: Sessions reset on deploy (acceptable for stability)
  if (!config.session) config.session = {};
  config.session.store = '/tmp/openclaw-sessions/{agentId}/sessions.json';
  config.session.dmScope = 'per-channel-peer';
  
  // SECURITY: Disable elevated tools by default on Railway
  if (!config.tools) config.tools = {};
  config.tools.elevated = { enabled: false };
  // Deny high-risk tool groups
  config.tools.deny = config.tools.deny || [];
  if (!config.tools.deny.includes('group:web')) {
    config.tools.deny.push('group:web');
  }
  
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
    
    // SECURITY: Use pairing mode with specific allowlist
    // - dmPolicy='pairing' requires approval before commands work
    // - allowFrom contains only your Telegram user ID
    config.channels.telegram.dmPolicy = 'pairing';
    config.channels.telegram.allowFrom = [OWNER_TELEGRAM_ID];
    config.channels.telegram.groupPolicy = 'disabled';  // No group access on Railway
    
    console.log('Telegram: dmPolicy=pairing, allowFrom=[' + OWNER_TELEGRAM_ID + ']');
  } else {
    console.log('WARNING: OPENCLAW_TELEGRAM_BOT_TOKEN not set - Telegram disabled');
  }
  
  // Discord configuration (token from OPENCLAW_DISCORD_TOKEN env var)
  const discordToken = process.env.OPENCLAW_DISCORD_TOKEN;
  if (discordToken) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.enabled = true;
    config.channels.discord.token = discordToken;
    delete config.channels.discord.botToken;  // Remove invalid key if present
    
    // SECURITY: Use pairing mode with specific allowlist
    config.channels.discord.dm = config.channels.discord.dm || {};
    config.channels.discord.dm.enabled = true;
    config.channels.discord.dm.policy = 'pairing';
    config.channels.discord.dm.allowFrom = [OWNER_DISCORD_ID];
    
    // SECURITY: Disable guild/group access on Railway
    config.channels.discord.groupPolicy = 'disabled';
    
    // STABILITY: Disable native commands to reduce startup work and API calls
    config.channels.discord.commands = { native: false, nativeSkills: false };
    
    // STABILITY: Minimal intents to reduce event volume and memory usage
    config.channels.discord.intents = { presence: false, guildMembers: false };
    
    console.log('Discord: dm.policy=pairing, dm.allowFrom=[' + OWNER_DISCORD_ID + '], commands=disabled');
  } else {
    console.log('WARNING: OPENCLAW_DISCORD_TOKEN not set - Discord disabled');
  }

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log('');
  console.log('=== Railway Security Configuration ===');
  console.log('Gateway:');
  console.log('  - bind: ' + config.gateway.bind + ' (0.0.0.0)');
  console.log('  - trustedProxies: ' + config.gateway.trustedProxies.length + ' Railway proxy IPs');
  console.log('  - auth.token: (from env, not in config)');
  console.log('Tools:');
  console.log('  - elevated.enabled: false');
  console.log('  - deny: ' + JSON.stringify(config.tools.deny));
  console.log('Sessions:');
  console.log('  - store: ' + config.session.store + ' (ephemeral /tmp for stability)');
  console.log('Channels:');
  console.log('  - telegram.dmPolicy: ' + (config.channels.telegram?.dmPolicy || 'n/a'));
  console.log('  - discord.dm.policy: ' + (config.channels.discord?.dm?.policy || 'n/a'));
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
