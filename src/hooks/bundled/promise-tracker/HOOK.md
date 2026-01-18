---
name: promise-tracker
description: "Inject open promises into agent context to ensure follow-through"
homepage: https://github.com/carmandale/clawdbot
metadata:
  clawdbot:
    emoji: "📋"
    events: ["agent"]
    install:
      - id: bundled
        kind: bundled
        label: "Bundled with Clawdbot"
---

# Promise Tracker Hook

Reads open promises from the ledger and injects them into the agent's context, ensuring the agent is aware of and accountable for prior commitments.

## The Problem

When a cron fires to follow up on a promise, the agent wakes fresh with no memory of:
- What it promised
- To whom
- In what context
- Why it matters

## The Solution

This hook runs at `agent:bootstrap` (before the agent's context is built) and:

1. Reads `~/.clawdbot/promises.jsonl`
2. Filters for `status: "open"` promises
3. Injects them into the agent's bootstrap context

## Injection Format

Open promises are injected into MEMORY.md context:

```
⚠️ OPEN COMMITMENTS (promise-tracker)
You have made the following promises that are still open:

1. [promise_abc123] To: +12143545107 (imessage)
   Due: 2026-01-18T13:30:00Z
   What: "I'll check back in 30 minutes"
   
2. [promise_xyz789] To: @carmandale23 (discord)
   Due: 2026-01-18T15:00:00Z
   What: "I'll follow up on the hooks implementation"

Address these commitments or mark them as fulfilled.
```

## Marking Promises Fulfilled

To mark a promise as fulfilled, update its status in the ledger:

```bash
# Manual: edit ~/.clawdbot/promises.jsonl
# Or use the promise tool (if available)
```

## Configuration

```json
{
  "hooks": {
    "internal": {
      "entries": {
        "promise-tracker": {
          "enabled": true,
          "maxAgeDays": 7,
          "ledgerPath": "~/.clawdbot/promises.jsonl"
        }
      }
    }
  }
}
```

## Companion Hook

Use with **promise-guard** (`message_sending`) to automatically detect and log promises.
