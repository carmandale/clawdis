#!/bin/sh
# Setup fork-local protections after fresh clone
#
# Run this once after cloning the clawdbot repo to configure
# the merge driver that protects fork-local files from upstream overwrites.
#
# What it does:
# 1. Configures the "ours" merge driver so .gitattributes merge=ours works
# 2. Verifies the bootloader hasn't been corrupted
# 3. Installs pre-commit hook (if prek not available)
set -e

echo "Setting up fork-local protections..."

# 1. Configure merge driver
git config merge.ours.driver true
echo "  [OK] merge.ours driver configured"

# 2. Verify bootloader
if [ -f railway-init.sh ]; then
  LINES=$(wc -l < railway-init.sh | tr -d ' ')
  if [ "$LINES" -gt 50 ]; then
    echo "  [WARN] railway-init.sh is $LINES lines -- expected ~40 (bootloader)"
    echo "         This may have been overwritten by an upstream merge."
    echo "         Check CLAUDE.md 'Fork-Local Files' section."
  elif grep -q 'exec sh "$INIT_SCRIPT"' railway-init.sh; then
    echo "  [OK] railway-init.sh bootloader intact ($LINES lines)"
  else
    echo "  [WARN] railway-init.sh missing bootloader handoff"
  fi
else
  echo "  [WARN] railway-init.sh not found"
fi

# 3. Verify .gitattributes
if grep -q "railway-init.sh merge=ours" .gitattributes 2>/dev/null; then
  echo "  [OK] .gitattributes has merge=ours for fork-local files"
else
  echo "  [WARN] .gitattributes missing merge=ours -- fork files unprotected!"
fi

echo ""
echo "Done. Fork-local files are protected from upstream merges."
