#!/bin/sh
# Railway init script - configure Chip agent for Railway deployment
#
# Architecture:
# - Uses declarative config from chipbot/config/railway.json5
# - No runtime JSON patching - config changes are version-controlled
# - Bot tokens come from env vars, not config file
#
# Required env vars:
# - OPENCLAW_GATEWAY_TOKEN: Auth token for internet-facing gateway
# - TELEGRAM_BOT_TOKEN (or OPENCLAW_TELEGRAM_BOT_TOKEN): Telegram bot token
# - DISCORD_BOT_TOKEN (or OPENCLAW_DISCORD_TOKEN): Discord bot token
# - SLACK_BOT_TOKEN + SLACK_APP_TOKEN: Slack tokens (if using Slack)

set -e

echo "[railway-init] Starting Railway gateway initialization..."

# ============================================
# STATE DIRECTORY SETUP
# ============================================

export OPENCLAW_STATE_DIR="/data/.clawdbot"

# Ensure directories exist (Railway volume may be empty on first deploy)
mkdir -p /data/.clawdbot/workspace
mkdir -p /data/.clawdbot/sessions

# Create ephemeral session directory for stability (fast I/O)
# Must include agent subdirectory since store path is {agentId}/sessions.json
mkdir -p /tmp/openclaw-sessions/main

echo "[railway-init] State directories created"

# ============================================
# SECURITY: REQUIRE GATEWAY TOKEN
# ============================================

if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  echo "ERROR: OPENCLAW_GATEWAY_TOKEN not set"
  echo "Refusing to start internet-facing gateway without auth"
  exit 1
fi

# ============================================
# LEGACY ENV VAR MAPPING
# ============================================
# Map legacy OPENCLAW_* token vars to canonical names for backward compatibility
# This allows gradual migration of Railway environment variables

if [ -z "$TELEGRAM_BOT_TOKEN" ] && [ -n "$OPENCLAW_TELEGRAM_BOT_TOKEN" ]; then
  export TELEGRAM_BOT_TOKEN="$OPENCLAW_TELEGRAM_BOT_TOKEN"
  echo "[railway-init] Mapped OPENCLAW_TELEGRAM_BOT_TOKEN -> TELEGRAM_BOT_TOKEN"
fi

if [ -z "$DISCORD_BOT_TOKEN" ] && [ -n "$OPENCLAW_DISCORD_TOKEN" ]; then
  export DISCORD_BOT_TOKEN="$OPENCLAW_DISCORD_TOKEN"
  echo "[railway-init] Mapped OPENCLAW_DISCORD_TOKEN -> DISCORD_BOT_TOKEN"
fi

# ============================================
# CLONE/PULL WORKSPACE
# ============================================

WORKSPACE_DIR="/data/.clawdbot/workspace/chipbot"

if [ -d "$WORKSPACE_DIR/.git" ]; then
  echo "[railway-init] Pulling latest workspace changes..."
  (cd "$WORKSPACE_DIR" && git pull --ff-only) || {
    echo "[railway-init] WARNING: git pull failed, continuing with existing workspace"
  }
else
  echo "[railway-init] Cloning workspace..."
  git clone https://github.com/carmandale/chipbot.git "$WORKSPACE_DIR" || {
    echo "ERROR: Failed to clone workspace"
    exit 1
  }
fi

echo "[railway-init] Workspace ready at $WORKSPACE_DIR"

# ============================================
# DECLARATIVE CONFIG SETUP
# ============================================
# Copy config from git workspace to state dir to keep workspace clean
# (doctor --fix may write backups; this avoids git-dirty issues)

CONFIG_SOURCE="$WORKSPACE_DIR/config/railway.json5"
CONFIG_TARGET="/data/.clawdbot/openclaw.json5"

if [ ! -f "$CONFIG_SOURCE" ]; then
  echo "ERROR: Declarative config not found at $CONFIG_SOURCE"
  echo "Ensure chipbot/config/railway.json5 exists in the repository"
  exit 1
fi

# Always copy fresh config from repo (ensures updates are applied on deploy)
cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
echo "[railway-init] Copied config: $CONFIG_SOURCE -> $CONFIG_TARGET"

export OPENCLAW_CONFIG_PATH="$CONFIG_TARGET"

# ============================================
# VERIFY CONFIGURATION
# ============================================

echo ""
echo "=== Railway Configuration ==="
echo "Config:    $OPENCLAW_CONFIG_PATH"
echo "Workspace: $WORKSPACE_DIR"
echo "State:     $OPENCLAW_STATE_DIR"
echo ""
echo "Channels:"
[ -n "$TELEGRAM_BOT_TOKEN" ] && echo "  - Telegram: enabled (token set)"
[ -z "$TELEGRAM_BOT_TOKEN" ] && echo "  - Telegram: disabled (no token)"
[ -n "$DISCORD_BOT_TOKEN" ] && echo "  - Discord: enabled (token set)"
[ -z "$DISCORD_BOT_TOKEN" ] && echo "  - Discord: disabled (no token)"
[ -n "$SLACK_BOT_TOKEN" ] && echo "  - Slack: enabled (token set)"
[ -z "$SLACK_BOT_TOKEN" ] && echo "  - Slack: disabled (no token)"
echo ""

# ============================================
# DOCTOR & GATEWAY
# ============================================

echo "[railway-init] Running doctor..."
node /app/dist/index.js doctor --fix || true

# Debug: show PORT value
echo "[railway-init] PORT env var: '${PORT}'"
GATEWAY_PORT="${PORT:-18789}"
echo "[railway-init] Starting gateway on port ${GATEWAY_PORT}..."
exec node /app/dist/index.js gateway run \
  --allow-unconfigured \
  --port "${GATEWAY_PORT}" \
  --bind lan
