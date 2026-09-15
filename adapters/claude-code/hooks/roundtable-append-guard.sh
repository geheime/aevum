#!/usr/bin/env bash
# roundtable-append-guard.sh — Claude Code PreToolUse hook for Edit|Write.
# Enforces the append-only round-table invariant (SPEC §5.4 / red-team MEDIO7):
# the round table is only ever appended via a shell `>>`, never rewritten by an
# edit tool — one careless overwrite silently deletes a CLAIM or RELEASE (a live
# front vanishes, or an orphan is resurrected). Best-effort, not cryptographic.
#
# Register in settings.json under hooks.PreToolUse for matchers Edit and Write.
# The hook reads the tool call as JSON on stdin; exit 2 blocks and shows stderr.
input="$(cat)"
fp="$(printf '%s' "$input" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//')"
case "$fp" in
  *_ROUNDTABLE.md)
    echo "The round table is append-only — do not Edit/Write it. Append one line with a shell redirect:" >&2
    echo "  printf '%s · <role> @ <front> · <EVENT> · sesión <id> · <note>\\n' \"\$(date '+%Y-%m-%d %H:%M')\" >> \"$fp\"" >&2
    exit 2 ;;
esac
exit 0
