# Investigation: Gateway Token Mismatch

## Summary
Gateway auth was broken due to stale device tokens in `~/.openclaw/identity/device-auth.json`. The TUI sends stored device tokens which override config tokens, so when the gateway token was changed, the stored device tokens became invalid.

## Symptoms
- Mac TUI: "gateway token mismatch (provide gateway auth token)"
- Railway TUI: Same error when connecting with `--token`
- `openclaw channels status --probe` failed with unauthorized

## Root Cause
The OpenClaw auth system uses **device tokens** (stored in `~/.openclaw/identity/device-auth.json`) that are issued during pairing. When connecting:

1. TUI checks for stored device token (`operator.token`)
2. If found, sends device token instead of `gateway.auth.token`
3. Gateway validates the device token against its paired devices list

When I changed `gateway.auth.token` and the LaunchAgent env var, the gateway's view of valid tokens changed, but the **local device-auth.json still had old device tokens** that were no longer valid.

## What I Did Wrong
1. Changed `OPENCLAW_GATEWAY_TOKEN` in LaunchAgent plist
2. Changed `gateway.auth.token` in config
3. Did NOT realize device tokens are separate from gateway auth tokens
4. Did NOT rotate/sync the device tokens after changing gateway auth

## Fix Applied
1. Used `openclaw devices rotate` to issue a new device token:
   ```bash
   openclaw devices rotate \
     --device 004bec9d98ecd977caf3ff6d5e57648d41bd5a2916c9a99157352b97833c9e60 \
     --role operator \
     --token 5749ba93a449b782b691acdc1b75f430
   ```
2. Manually updated `~/.openclaw/identity/device-auth.json` with the new token
   (Note: The rotate command updated gateway but didn't auto-sync local file)

## Current Status
- ✅ Mac local gateway: Working (`openclaw channels status --probe` succeeds)
- ⏳ Railway: Configured correctly, needs user to test TUI connection

## Key Learnings
1. **Device tokens ≠ Gateway auth tokens**
   - `gateway.auth.token`: Shared secret for initial auth
   - `device-auth.json`: Paired device tokens issued by gateway
   - Device tokens take precedence over config tokens

2. **Token resolution order (TUI)**:
   - opts.token (CLI flag)
   - Stored device token (if paired)
   - OPENCLAW_GATEWAY_TOKEN (env)
   - gateway.auth.token (config)

3. **When changing gateway tokens**, must also:
   - Rotate device tokens: `openclaw devices rotate`
   - Or revoke and re-pair devices

## Files Involved
- `~/.openclaw/identity/device-auth.json` - Stored device tokens
- `~/.openclaw/openclaw.json` - Config with gateway.auth.token
- `~/Library/LaunchAgents/ai.openclaw.gateway.plist` - Gateway service env vars
