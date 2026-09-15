# Ritual — close (standing up)

1. **Log** the session; distill any durable lessons.
2. **Reconcile against disk:** re-read git + round table + batons.
3. **Write your baton through compare-and-swap**, using the sha you recorded at
   boot:
   ```
   bin/baton-cas.sh write <house>/_BATON_<role>.md <boot-sha> < <new-baton>
   ```
   - **CAS ok** → written atomically.
   - **CONFLICT** → another same-role instance closed while you worked. Re-read
     the baton on disk, **MERGE** its testimony with yours, and retry with the
     new sha. Never overwrite.
4. **RELEASE** your front on the round table, reproducing your CLAIM's `<role> @ <front>`
   and `sesión <id>` **exactly** (or it will not match):
   ```
   printf '%s · %s @ %s · RELEASE · sesión %s · %s\n' \
     "$(date '+%Y-%m-%d %H:%M')" "<role>" "<front>" "<session-id>" "<note>" \
     >> <house>/_ROUNDTABLE.md
   ```
5. **Append a node** to `<house>/_LINAJE.md`:
   `- **gen <N>** · <date> · <what this generation did>`
