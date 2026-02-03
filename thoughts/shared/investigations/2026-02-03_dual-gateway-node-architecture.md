# Investigation: Dual Gateway + Node Architecture

## Summary

**CONFIRMED: Mac can run BOTH a local gateway AND be a node to Railway simultaneously.** They are separate processes using different config files and don't conflict.

## Desired Architecture

```
┌─────────────────────────────────────────────────────────────┐
│               RAILWAY GATEWAY (24/7 Cloud)                   │
│  Channels: Telegram, Discord, Slack                          │
│  Workspace: /data/.clawdbot/workspace/chipbot                │
└─────────────────────────────────────────────────────────────┘
          ↑                                    ↑
          │ WebSocket (node)                   │ Telegram/Discord/Slack
          │                                    │
┌─────────┴───────────────────────────────────┴───────────────┐
│               MAC (Local)                                    │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │ Gateway (local)     │    │ Node Host           │         │
│  │ Port: 18789         │    │ → connects to       │         │
│  │ Config: openclaw.json│   │   Railway WS        │         │
│  │ TUI connects here   │    │ Config: node.json   │         │
│  └─────────────────────┘    └─────────────────────┘         │
│  Workspace: ~/chipbot                                        │
└─────────────────────────────────────────────────────────────┘
          ↑
          │ TUI (Ghostty)
          │
```

## Evidence

### 1. Node Host is a WebSocket Client (No Port Binding)

**Source:** `src/node-host/runner.ts`, `src/gateway/client.ts`

```typescript
// Node host uses GatewayClient which is a WS client
import { GatewayClient } from "../gateway/client.js";

// GatewayClient connects via WebSocket, doesn't listen
import { WebSocket } from "ws";
```

**Finding:** Node host only makes OUTBOUND connections to a remote gateway. It does NOT bind any ports.

### 2. Separate Config Files

**Source:** `src/node-host/config.ts`, `src/config/paths.ts`

| Component | Config File | Contents |
|-----------|-------------|----------|
| Gateway | `~/.openclaw/openclaw.json` | channels, agents, gateway settings |
| Node Host | `~/.openclaw/node.json` | nodeId, displayName, gateway connection |

**Finding:** They use DIFFERENT config files in the same state directory. No conflict.

### 3. FAQ Confirms Architecture

**Source:** `docs/help/faq.md`

> "Do nodes run a gateway service? No. Only **one gateway** should run per host... Nodes are peripherals that connect to the gateway"

**Finding:** The "one gateway per host" rule refers to running multiple GATEWAYS, not gateway + node. Node is a peripheral, not a gateway.

### 4. Port Usage

| Service | Ports | Binds? |
|---------|-------|--------|
| Gateway | 18789 (WS/HTTP), 18791 (browser), 18793 (canvas) | Yes |
| Node Host | None | No (outbound WS only) |
| TUI | None | No (connects to gateway WS) |

**Finding:** No port conflicts possible.

### 5. Process Independence

- Gateway: `openclaw gateway run` or menubar app
- Node Host: `openclaw node run --host <remote>` or LaunchAgent service
- TUI: `openclaw tui` connects to local gateway

Each is a separate process. They can run simultaneously.

## Architecture Validation

### What Works

1. **Mac runs local gateway** → TUI connects for fast local access
2. **Mac runs node host** → Connects to Railway, provides Mac capabilities
3. **Railway runs gateway** → Handles Telegram/Discord/Slack 24/7
4. **Git sync** → Keeps `~/chipbot` workspace synchronized

### Session Isolation

| Gateway | Session Store | Transcripts |
|---------|---------------|-------------|
| Mac | `~/chipbot/sessions/mac/{agentId}/sessions.json` | `~/.openclaw/agents/main/sessions/*.jsonl` |
| Railway | `/data/.../sessions/railway/.../sessions.json` | Railway state dir |

Sessions are isolated by gateway. qmd indexes both for cross-gateway search.

### Service Configuration

**Mac Gateway** (already configured):
- `gateway.mode: local`
- `gateway.bind: loopback`
- `gateway.port: 18789`

**Mac Node Host** (current `node.json`):
```json
{
  "nodeId": "e8a61e1d-4455-4786-8d8c-f87d5982c0e2",
  "displayName": "Dale's MacBook Pro M4",
  "gateway": {
    "host": "clawdbot-production-3c52.up.railway.app",
    "port": 443,
    "tls": true
  }
}
```

## Recommended Setup

### 1. Mac Services

| Service | LaunchAgent | Purpose |
|---------|-------------|---------|
| Gateway | `ai.openclaw.gateway` (or app) | Local TUI access |
| Node Host | `ai.openclaw.node` | Railway Mac capabilities |

### 2. Channel Assignment

| Channel | Gateway | Rationale |
|---------|---------|-----------|
| Telegram | Railway | 24/7 mobile access |
| Discord | Railway | 24/7 mobile access |
| Slack | Railway | 24/7 access |
| TUI | Mac (local) | Fast, direct, full control |

### 3. Disable Messaging Channels on Mac

Mac gateway should NOT run Telegram/Discord/Slack to avoid conflicts:
```json
{
  "channels": {
    "telegram": { "enabled": false },
    "discord": { "enabled": false },
    "slack": { "enabled": false }
  }
}
```

## Conclusion

The desired architecture is **fully supported** and **validated by code analysis**:

1. ✅ Mac can run local gateway for TUI
2. ✅ Mac can simultaneously be a node to Railway
3. ✅ No port conflicts (node is client-only)
4. ✅ No config conflicts (separate files)
5. ✅ Git sync keeps workspaces aligned
6. ✅ qmd provides cross-gateway search

**Next Steps:**
1. Ensure Mac gateway is running (for TUI)
2. Ensure Mac node host is running (for Railway capabilities)
3. Disable messaging channels on Mac gateway (avoid conflicts with Railway)
4. Set up git sync cron
