# Investigation: Dual Gateway QMD Integration

## Summary

qmd is correctly configured to index sessions from both gateways. The "mac-legacy" collection is actually indexing CURRENT Mac sessions (not legacy). Key integration gaps: external hooks not wired, qmd MCP not configured, embeddings incomplete.

## Architecture Discovery

### Critical Finding: Session Store vs Transcript Paths

| Component | Location | Configurable |
|-----------|----------|--------------|
| Session INDEX (`sessions.json`) | `~/chipbot/sessions/mac/main/sessions.json` | ✅ Yes via `session.store` |
| Session TRANSCRIPTS (`.jsonl`) | `~/.openclaw/agents/main/sessions/*.jsonl` | ❌ No, always in stateDir |

**Key insight:** `session.store` config only moves the INDEX file, not the transcripts. Transcripts always go to `~/.openclaw/agents/{agentId}/sessions/` (controlled by `OPENCLAW_STATE_DIR` env var).

### Session File Locations

```
Mac Gateway:
├── Session Index: ~/chipbot/sessions/mac/main/sessions.json (1.3 MB)
├── Transcripts: ~/.openclaw/agents/main/sessions/*.jsonl (994 files)
└── Workspace: ~/chipbot/

Railway Gateway:
├── Session Index: ~/chipbot/sessions/railway/main/sessions.json
├── Transcripts: ~/chipbot/sessions/railway/main/*.jsonl (3 files, synced via git)
└── Workspace: ~/chipbot/ (same repo, different subdirectory)
```

## qmd Integration Status

### Collections (correctly configured)

| Collection | Path | Files | Notes |
|------------|------|-------|-------|
| `mac-legacy` | `~/.openclaw/agents/main/sessions/` | 994 | **CURRENT Mac sessions** (name misleading) |
| `chip-sessions` | `~/chipbot/sessions/` | 4 | Railway sessions + test file |
| `chip-memory` | `~/chipbot/memory.md` | 1 | Shared memory |
| `chip-memory-dir` | `~/chipbot/memory/**/*.md` | 28 | Memory directory |

### Index Status

```
Total indexed: 1,027 files
Vectors embedded: 18,130 chunks (31%)
Pending: 646 chunks need embedding
Index size: 273.4 MB
```

### Search Verification

✅ BM25 keyword search works immediately:
```bash
qmd search "dual gateway" -n 3  # Returns relevant results
```

⚠️ Vector/semantic search requires embeddings to complete:
```bash
qmd vsearch "cross-gateway knowledge"  # Limited until embeddings done
```

## Hooks Analysis

### Hooks Directory (`~/chipbot/hooks/`)

| Hook | Purpose | Status |
|------|---------|--------|
| `gateway-sync` | Pulls git, generates CATCHUP.md | ✅ Implemented, ❌ Not wired |
| `catchup-inject` | Injects CATCHUP.md into agent bootstrap | ✅ Implemented, ❌ Not wired |
| `compaction-summary` | Reminder for cron setup | ✅ Implemented, ❌ Not wired |

### Current Hook Configuration

```json
// ~/.openclaw/openclaw.json
"hooks": {
  "internal": {
    "enabled": true,
    "entries": {
      "boot-md": { "enabled": true },
      "command-logger": { "enabled": true },
      "promise-tracker": { "enabled": true },
      "session-memory": { "enabled": true }
    }
  }
  // NO external "handlers" array configured!
}
```

## Integration Gaps

### 1. External Hooks Not Wired

**Fix:** Add handlers array to `~/.openclaw/openclaw.json`:
```json
"hooks": {
  "internal": { ... },
  "handlers": [
    { "event": "gateway:startup", "module": "~/chipbot/hooks/gateway-sync/handler.ts" },
    { "event": "agent:bootstrap", "module": "~/chipbot/hooks/catchup-inject/handler.ts" }
  ]
}
```

### 2. qmd MCP Not Configured

qmd has MCP server capability (`qmd mcp`). Options:
- Add as MCP server in openclaw config (if supported)
- Create a custom tool wrapper
- Use directly via bash tool calls

### 3. Embeddings Incomplete

```bash
# Complete in background
nohup qmd embed > /tmp/qmd-embed.log 2>&1 &
```

### 4. No Auto-Update Cron

```bash
# Add to crontab
0 5 * * * export PATH="$HOME/.bun/bin:$PATH" && qmd update && qmd embed
```

### 5. Collection Naming Misleading

Rename for clarity:
```bash
qmd collection rename mac-legacy mac-sessions
```

## Cross-Gateway Search Flow

### Current (Working)

```
User on Mac → Agent → bash tool → qmd search "query"
                                       ↓
                         Searches: mac-sessions + chip-sessions + memory
                                       ↓
                         Returns: Results from both gateways
```

### Enhanced (With hooks wired)

```
Gateway Startup → gateway-sync hook → git pull + generate CATCHUP.md
                                              ↓
Agent Bootstrap → catchup-inject hook → Inject CATCHUP.md into context
                                              ↓
                         Agent knows about recent cross-gateway activity
```

## Recommendations

### Immediate (Priority 1)

1. **Rename collection for clarity:**
   ```bash
   qmd collection rename mac-legacy mac-sessions
   ```

2. **Complete embeddings:**
   ```bash
   nohup qmd embed > /tmp/qmd-embed.log 2>&1 &
   ```

3. **Wire external hooks** - Edit `~/.openclaw/openclaw.json`

### Short-term (Priority 2)

4. **Set up auto-update cron:**
   ```bash
   crontab -e
   # Add: 0 5 * * * export PATH="$HOME/.bun/bin:$PATH" && qmd update && qmd embed
   ```

5. **Start git sync for sessions** (already documented in research)

### Optional (Priority 3)

6. **MCP integration** - If OpenClaw supports custom MCP servers
7. **Create qmd wrapper tool** - For cleaner agent integration

## Verification Commands

```bash
# Check qmd status
qmd status

# Test cross-gateway search
qmd search "telegram" -c mac-sessions  # Should find Mac discussions about Telegram
qmd search "mac" -c chip-sessions      # Should find Railway discussions about Mac

# Check collection contents
qmd ls mac-sessions | head
qmd ls chip-sessions

# Verify hooks are wired (after config update)
cat ~/.openclaw/openclaw.json | jq '.hooks.handlers'
```

## Evidence

- Session path resolution: `src/config/sessions/paths.ts` lines 36-47
- stateDir default: `src/config/paths.ts` - always `~/.openclaw/`
- qmd config: `~/.config/qmd/index.yml`
- qmd index: `~/.cache/qmd/index.sqlite` (273.4 MB)
