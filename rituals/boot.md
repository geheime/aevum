# Ritual — boot (sitting down)

You are a fresh instance sitting a seat. You were born without memory; the baton
and the SPEC are your only continuity. **Ingest → verify → think.** Touch nothing
until you have a plan.

1. Resolve the house and your role. Read `<house>/_BATON_<role>.md`.
2. **Record its sha** — you need it to close safely:
   `bin/baton-cas.sh sha <house>/_BATON_<role>.md`
3. **Triple-check** the baton against the raw source (git log, the tracker). The
   baton can lie: an instance may have inferred instead of read. Flag every
   discrepancy before proceeding.
4. **Reclaim orphans** left by dirty deaths, and surface them:
   `adapters/<host>/reclaim.sh all <house>/_ROUNDTABLE.md`
   A human decides the reclaim; you only report.
5. **Read the live round table** for fronts that collide with yours:
   `bin/roundtable.sh live <house>/_ROUNDTABLE.md`
6. **Plan.** Present who you are, the verified state, and one concrete next
   action. Act only on approval.
7. **On starting real work, append your CLAIM** (until you do, your front is not
   LIVE and your close has no anchor):
   ```
   printf '%s · %s @ %s · CLAIM · sesión %s · %s\n' \
     "$(date '+%Y-%m-%d %H:%M')" "<role>" "<front>" "<session-id>" "<note>" \
     >> <house>/_ROUNDTABLE.md
   ```

**Founding:** no baton for your role → you are founding the seat (`gen 1`); its
boot sha is `NONE`.
