# Claude Code adapter — /close

A Claude Code slash-command that runs the close ritual. Install at
`~/.claude/commands/close.md`. It follows [`rituals/close.md`](../../../rituals/close.md).

Command body (sketch):

```
Follow rituals/close.md for the current seat.
Log and distill; reconcile against disk; write the baton via
baton-cas.sh write <baton> <boot-sha> — on CONFLICT, merge with disk and retry;
RELEASE the front on the MESA (exact key); append the lineage node.
```

The critical binding is the **boot sha**: the `/boot` command recorded it when it
ingested the baton, and `/close` passes it to the CAS. That single value is what
turns "you merge, you do not overwrite" from prose into mechanism.
