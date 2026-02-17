#!/bin/sh
# ╔═══════════════════════════════════════════════════════════════════╗
# ║  FORK-LOCAL BOOTLOADER — DO NOT OVERWRITE WITH UPSTREAM CHANGES  ║
# ║                                                                   ║
# ║  This file is protected by .gitattributes (merge=ours).           ║
# ║  It is a ~30 line bootloader that clones the chipbot workspace    ║
# ║  and hands off to chipbot/railway-init.sh for all customization.  ║
# ║                                                                   ║
# ║  If this file grows beyond ~40 lines, something is WRONG.         ║
# ║  All Railway init logic belongs in chipbot, not here.             ║
# ╚═══════════════════════════════════════════════════════════════════╝
set -e

WORKSPACE_DIR="/data/.clawdbot/workspace/chipbot"
WORKSPACE_REPO="https://github.com/carmandale/clawdbot-workspace.git"
# Use GITHUB_TOKEN for private repo access if available
if [ -n "$GITHUB_TOKEN" ]; then
  WORKSPACE_REPO="https://${GITHUB_TOKEN}@github.com/carmandale/clawdbot-workspace.git"
fi

echo "[bootloader] Starting workspace bootstrap..."

mkdir -p /data/.clawdbot/workspace

if [ -d "$WORKSPACE_DIR/.git" ]; then
  echo "[bootloader] Pulling latest workspace..."
  # Clean up stale lock files from previous container crashes
  rm -f "$WORKSPACE_DIR/.git/index.lock" "$WORKSPACE_DIR/.git/HEAD.lock" 2>/dev/null || true
  (cd "$WORKSPACE_DIR" && git remote set-url origin "$WORKSPACE_REPO" && git pull --ff-only) || {
    echo "[bootloader] WARNING: git pull failed, continuing with existing workspace"
  }
else
  echo "[bootloader] Cloning workspace..."
  git clone "$WORKSPACE_REPO" "$WORKSPACE_DIR" || {
    echo "[bootloader] ERROR: Failed to clone workspace"
    exit 1
  }
fi

INIT_SCRIPT="$WORKSPACE_DIR/railway-init.sh"
if [ ! -f "$INIT_SCRIPT" ]; then
  echo "[bootloader] ERROR: $INIT_SCRIPT not found in workspace"
  exit 1
fi

echo "[bootloader] Handing off to workspace init script..."
exec sh "$INIT_SCRIPT"
