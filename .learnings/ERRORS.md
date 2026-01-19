## [ERR-20260119-001] bd

**Logged**: 2026-01-19T10:16:13Z
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
`bd create` failed because no beads database was initialized

### Error
```
Error: no beads database found
Hint: run 'bd init' to create a database in the current directory
      or use 'bd --no-db' to work with JSONL only (no SQLite)
      or set BEADS_DIR to point to your .beads directory
```

### Context
- Command attempted: `bd create --title="Fix OpenAI responses reasoning orphan history" --type=bug --priority=2`
- Working directory: `/Users/dalecarman/clawdbot`

### Suggested Fix
Run `bd init` in the repo or use `bd --no-db` for JSONL-only tracking.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

---
## [ERR-20260119-002] restart-mac

**Logged**: 2026-01-19T10:18:41Z
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
`./scripts/restart-mac.sh --no-sign` failed during Swift build of Peekaboo dependency

### Error
```
error: emit-module command failed with exit code 1 (use -v to see invocation)
.../PeekabooBridgeModels.swift:812:30: error: 'retroactive' attribute does not apply; 'PermissionsStatus' is declared in the same package
ERROR: swift build failed
```

### Context
- Command attempted: `./scripts/restart-mac.sh --no-sign`
- Failing file: `apps/macos/.build/checkouts/Peekaboo/Core/PeekabooCore/Sources/PeekabooBridge/PeekabooBridgeModels.swift:812`

### Suggested Fix
Investigate the Peekaboo dependency version or local toolchain; remove `@retroactive` or update the dependency/toolchain if needed.

### Metadata
- Reproducible: unknown
- Related Files: scripts/restart-mac.sh
- See Also: ERR-20260119-001

---
