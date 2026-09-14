# Claude Code adapter — /boot

A Claude Code slash-command that runs the boot ritual. Install at
`~/.claude/commands/boot.md`. It follows [`rituals/boot.md`](../../../rituals/boot.md),
binding the two host-specific pieces:

- **session id** (SPEC §5.1) — the first 6 hex of this session's transcript UUID.
  Prefer a longer id; 6 chars can collide (see SPEC Known limitations).
- **liveness** (SPEC §5.2) — `reclaim.sh` derives it from the transcript mtime
  (`~/.claude/projects/*/<uuid>.jsonl`, appended every turn).

Command body (sketch):

```
Follow rituals/boot.md for the house named in $ARGUMENTS.
Resolve the baton, record its sha, triple-check against git and the tracker,
run reclaim.sh all <house>/_MESA.md, read mesa.sh live, and present a plan in
plan mode. Touch nothing until approved. On approval, append the CLAIM.
```

This is the portable skeleton. A production command additionally carries the
operator's house-resolution (where houses live on disk) and their reclaim wiring.
