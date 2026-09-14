#!/usr/bin/env bash
# baton-cas.sh — compare-and-swap for the baton. Closes the TOCTOU on a
# concurrent same-role close: two instances of one role closing at nearly the
# same time used to overwrite each other's baton SILENTLY, losing a generation.
# Now a write happens ONLY if the baton on disk is still identical to the one you
# read at boot; if it changed, it ABORTS loudly and demands a merge.
#
# The "409" the SPEC names was advisory (it detected, it did not prevent). This
# makes it a mechanism: a blind overwrite becomes impossible-without-noticing.
#
# Usage:
#   baton-cas.sh sha   <BATON_FILE>                  # current sha (or NONE if absent) — boot records it
#   baton-cas.sh write <BATON_FILE> <EXPECTED_SHA>   # writes stdin IFF current sha == EXPECTED_SHA
#
# Founding: an absent baton => sha NONE. The boot of a gen-1 seat records NONE;
# if another instance already founded it by close time (sha != NONE), that is a
# real CONFLICT.
#
# Honesty (see the SPEC "Known limitations"): the window between the sha check
# and the mv is tiny but not zero (no portable flock on macOS). It turns a
# guaranteed, silent clobber into an improbable TOCTOU; it does not remove it.
#
# — Designed by Humans · Built by Intelligence
set -euo pipefail

cmd="${1:-}"; baton="${2:-}"

usage() { echo "usage: baton-cas.sh sha <BATON_FILE>  |  baton-cas.sh write <BATON_FILE> <EXPECTED_SHA> < content" >&2; exit 2; }

sha_of() {  # sha256 of the file, or NONE if it does not exist
  local f="$1"
  [ -f "$f" ] || { printf 'NONE\n'; return 0; }
  if   command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum   "$f" | awk '{print $1}'
  else echo "baton-cas: neither shasum nor sha256sum on PATH" >&2; return 3; fi
}

case "$cmd" in
  sha)
    [ -n "$baton" ] || usage
    sha_of "$baton"
    ;;
  write)
    expected="${3:-}"
    { [ -n "$baton" ] && [ -n "$expected" ]; } || usage
    current="$(sha_of "$baton")"
    if [ "$current" != "$expected" ]; then
      echo "CONFLICT: the baton changed since your boot (expected $expected, on disk $current)." >&2
      echo "  Another instance of your role wrote while you worked — NOT overwriting." >&2
      echo "  Re-read $baton, MERGE your testimony with disk, and retry with the new sha." >&2
      exit 1
    fi
    dir="$(dirname "$baton")"
    tmp="$(mktemp "$dir/.baton.XXXXXX")"
    cat > "$tmp"
    mv -f "$tmp" "$baton"          # mv on the same filesystem is atomic
    echo "baton written (CAS ok: $expected)."
    ;;
  *) usage ;;
esac
