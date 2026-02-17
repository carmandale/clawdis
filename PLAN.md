# Plan: Add GET /health endpoint to OpenClaw gateway

## Research Summary

**Current state:**

- `render.yaml` already declares `healthCheckPath: /health` but no HTTP handler exists
- `railway.toml` has no healthcheck configuration
- Gateway has WS-based health via `server-methods/health.ts` using cached `HealthSummary`
- `health-state.ts` exposes `getHealthCache()` returning `HealthSummary | null`
- `HealthSummary` contains `ok: true`, `ts: number`, plus detailed channel/agent/session data
- `server-http.ts` has a `handleRequest` chain: hooks -> tools -> slack -> plugins -> openResponses -> openAI -> canvas -> controlUI -> 404
- Existing `sendJson()` helper already available in `server-http.ts`

## Implementation Plan

### 1. Edit `src/gateway/server-http.ts`

**Import:** Add `getHealthCache` from `./server/health-state.js`

**Add health handler function** (module-level, before `createGatewayHttpServer`):

```typescript
function handleHealthRequest(req: IncomingMessage, res: ServerResponse): boolean {
  const url = req.url ?? "/";
  if (
    url !== "/health" &&
    url !== "/healthz" &&
    !url.startsWith("/health?") &&
    !url.startsWith("/healthz?")
  ) {
    return false;
  }
  const cached = getHealthCache();
  if (cached) {
    sendJson(res, 200, { ok: true, ts: cached.ts });
  } else {
    sendJson(res, 503, { ok: false, ts: 0 });
  }
  return true;
}
```

**Insert into handleRequest:** Place the health check as the FIRST thing inside the `try` block of `handleRequest`, before `loadConfig()` and before hooks:

```typescript
// line ~248, inside try block, before const configSnapshot = loadConfig();
if (handleHealthRequest(req, res)) {
  return;
}
```

**Key design decisions:**

- Returns `{ok: boolean, ts: number}` only -- no channel details, no bot names (safe for unauthenticated probes)
- `200` when cache exists (gateway is up and has run at least one health check), `503` when null (still starting)
- Uses `getHealthCache()` -- zero-cost read of an in-memory variable, no deep probes triggered per request
- Placed FIRST in handler chain -- before config load, before hooks, before auth. Health probes from Railway/Render are unauthenticated and must not be blocked.
- Supports both `/health` and `/healthz` (common k8s convention)
- Synchronous function (no async needed since it reads a cached value)
- URL matching handles query strings (e.g. `/health?verbose=1` still matches)

### 2. Edit `railway.toml`

Add healthcheck configuration:

```toml
[deploy]
healthcheckPath = "/health"
healthcheckTimeout = 30
```

### 3. No new test file needed

The existing `server.health.e2e.test.ts` tests WS-based health. For the HTTP `/health` endpoint, I will verify via `pnpm build && pnpm test` that nothing breaks. The HTTP health handler is intentionally minimal and deterministic (reads a cached value, returns JSON), making it low-risk. If the team wants dedicated HTTP health tests, that can be a follow-up.

## Files touched

- `src/gateway/server-http.ts` (edit: add import + handler function + early-return in handleRequest)
- `railway.toml` (edit: add healthcheck config)

## Estimated scope: Small

- ~15 lines of new code in server-http.ts
- ~3 lines added to railway.toml
