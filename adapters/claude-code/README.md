# Reference adapter — Claude Code

Binds the Aevum protocol (see [`../../SPEC.md`](../../SPEC.md)) to Claude Code.
It provides the three host-specific pieces from SPEC §5:

| SPEC §5 | Here |
|---|---|
| 5.1 session id | first 6 hex of the session transcript UUID (prefer longer — see Known limitations) |
| 5.2 liveness signal | [`reclaim.sh`](reclaim.sh) reads the transcript mtime (a per-turn heartbeat) + the browser-lock PID |
| 5.3 ritual invocation | slash-commands in [`commands/`](commands/) → `rituals/` |
| 5.4 guards | [`hooks/roundtable-append-guard.sh`](hooks/roundtable-append-guard.sh) enforces the append-only round table |

The portable core (`bin/roundtable.sh`, `bin/baton-cas.sh`, `templates/`, `tests/`) is
shared and lives at the repo root — nothing Claude-specific there. Another CLI
binds by re-implementing this folder.
