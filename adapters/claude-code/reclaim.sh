#!/usr/bin/env bash
# reclaim.sh — recovers resources left dangling when an instance dies DIRTY
#              (crash / kill / context saturation) without reaching `close`. The
#              harness safety net (baton, RELEASE, lineage) is voluntary: it is
#              woven only if the instance lives. This covers it from the OTHER
#              side — the one who cleans the corpse is the NEXT instance, not the
#              dying one.
#
# WHY A .sh AND NOT INLINE (same as mesa.sh): awk's $N collide with a host
#   command's positional-argument substitution (a boot with a multi-word arg
#   replaces $1,$2,… with the arg's words) → a mute parser that LIES. A real .sh
#   has no slash-command expansion. The ritual text only CALLS it.
#
# THE KEY INSIGHT (2026-08-24): you do NOT need to build a TTL/heartbeat. Two
#   liveness signals already exist, for free:
#   1. The Playwright lock carries the PID: `SingletonLock` → symlink to
#      `<host>-<PID>`. kill -0 that PID (and confirm it is a chrome of THIS
#      userDataDir, in case the PID was recycled) = deterministic, zero false
#      positives.
#   2. The session transcript is the heartbeat: each CLAIM records `sesión <id>`,
#      which maps to ~/.claude/projects/*/<uuid>.jsonl; the host appends to it
#      every turn. Its mtime says how long ago that session breathed.
#
# Usage:
#   reclaim.sh playwright [--dry]          # Layer 1: sweep orphaned Chrome locks (default: sweep)
#   reclaim.sh claims <MESA_FILE>          # Layer 2: report live/doubtful/orphaned CLAIMs (does NOT mutate the MESA)
#   reclaim.sh all <MESA_FILE> [--dry]     # both, for the boot ritual
#
# Layer 2 NEVER deletes from the MESA (append-only + no total certainty): it only
# REPORTS. Reclaiming an orphaned CLAIM is a human decision at seating. Layer 2
# prints the RELEASE line ready to copy, with the dead `<role> @ <front>` EXACT —
# the key must CLONE the CLAIM letter for letter or the RELEASE will not match and
# the orphan stays live forever (red-team ALTO5). Append it with the current date,
# so the RELEASE does not depend on the live corpse.
#
# — Designed by Humans · Built by Intelligence

set -euo pipefail

PW_CACHE="${RECLAIM_PW_CACHE:-$HOME/Library/Caches/ms-playwright-mcp}"   # override for tests
PROJECTS="${RECLAIM_PROJECTS:-$HOME/.claude/projects}"                   # override for tests
LIVE_SEC="${RECLAIM_LIVE_SEC:-600}"    # < 10min without breathing = ALIVE
DEAD_SEC="${RECLAIM_DEAD_SEC:-3600}"   # ≥ 1h without breathing = likely ORPHAN ; in between = DOUBTFUL
MESA_SH="${MESA_SH:-}"                  # override for tests / non-standard install

# resolve the mesa.sh parser: sibling in a flat install (~/.claude/bin) or
# ../../bin in the repo layout (adapters/claude-code/). Fail LOUD if absent — a
# silenced parser call IS the false-clean this system exists to prevent
# (red-team CRIT1: reclaim in adapters/, mesa.sh in bin/, NOT siblings).
resolve_mesa() {
  local d c; d="$(cd "$(dirname "$0")" && pwd)"
  if [ -n "$MESA_SH" ] && [ -x "$MESA_SH" ]; then printf '%s\n' "$MESA_SH"; return 0; fi
  for c in "$d/mesa.sh" "$d/../../bin/mesa.sh"; do
    [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

cmd="${1:-}"

usage() {
  echo "usage: reclaim.sh playwright [--dry|--kill]  |  reclaim.sh claims <MESA_FILE>  |  reclaim.sh all <MESA_FILE> [--dry]" >&2
  echo "       --kill: kills the ALIVE-BUT-OWNERLESS chrome (Layer 1b) and sweeps Singleton*. By hand only, never from boot." >&2
  exit 2
}

# ── Layer 1 ── orphaned Playwright lock ───────────────────────────────────────
# The SingletonLock is a symlink to "<host>-<PID>". Alive AND of this userDataDir
# = legitimately in use (leave it). Dead, or PID recycled by another process =
# orphan → sweep.
#
# ── Layer 1b (v2.6.2) ── the ALIVE corpse: the Playwright MCP dies/restarts and
# its chrome keeps breathing on about:blank; the new MCP tries to relaunch →
# "Browser is already in use". Layer 1 does NOT touch it (live PID + chrome of
# this userDataDir = its "in use" condition). The signal that already exists: the
# chrome is launched by the playwright-mcp process (chain: cli → npm exec → node
# playwright-mcp → chrome). If the MCP died, the chrome is REPARENTED (ppid =
# launchd or something that is not playwright-mcp) → alive but ownerless. It
# reports + leaves the kill ready; it runs only with --kill (by hand, human-
# gated). Never --isolated at the root: that loses the browser session/cookies.
# Known limit: if the SAME MCP is still alive but lost the handle, the ppid is
# legitimate and this layer cannot see it — that needs the manual kill.
reclaim_playwright() {
  local dry="${1:-}"; local kill_mode="${2:-}"
  local swept=0 alive=0 zombies=0
  [ -d "$PW_CACHE" ] || { echo "  · Playwright: no cache ($PW_CACHE) — nothing to sweep"; return 0; }
  local dir base lock target pid
  for dir in "$PW_CACHE"/*/; do
    [ -d "$dir" ] || continue
    lock="${dir}SingletonLock"
    [ -e "$lock" ] || [ -L "$lock" ] || continue
    base=$(basename "$dir")
    if [ ! -L "$lock" ]; then
      echo "  ⚠ Playwright: $base has a SingletonLock that is NOT a symlink — unusual, NOT touching it (check by hand)"
      continue
    fi
    target=$(readlink "$lock"); pid="${target##*-}"
    # "of this userDataDir" = its argv contains the FULL PATH of the dir (not the
    # basename: that would be a loose substring). Chrome runs with --user-data-dir=<dir>.
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
         && ps -p "$pid" -o command= 2>/dev/null | grep -qF -- "${dir%/}"; then
      # Layer 1b: who is the parent? a legit chrome is a child of playwright-mcp.
      local ppid pcmd
      ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      pcmd=$(ps -o command= -p "${ppid:-0}" 2>/dev/null || true)
      # legit parent = the MCP server: a node process running playwright-mcp / mcp-server-playwright.
      # STRICT match (not "contains playwright"): a shell whose line mentions playwright (e.g. the zsh
      # running this very script) is NOT the owner — a false "in use" seen in testing.
      if grep -qE '^([^ ]*/)?node .*(playwright-mcp|mcp-server-playwright|@playwright/mcp)' <<<"$pcmd"; then
        echo "  · Playwright: $base IN USE (PID $pid alive, chrome of this userDataDir, parent playwright-mcp $ppid) — leaving it"
        alive=$((alive+1))
      else
        zombies=$((zombies+1))
        if [ -n "$kill_mode" ]; then
          kill -9 "$pid" 2>/dev/null || true
          sleep 1
          rm -f "${dir}Singleton"* 2>/dev/null || true
          echo "  🧟 Playwright: $base ALIVE-BUT-OWNERLESS → KILLED (PID $pid, parent was '$ppid ${pcmd:0:40}') + Singleton* swept — relaunch the MCP"
        else
          echo "  🧟 Playwright: $base ALIVE-BUT-OWNERLESS (PID $pid breathes, but its parent $ppid is '${pcmd:0:40}', not playwright-mcp → the MCP that launched it died). NOT touching it alone."
          echo "     To reclaim it (gated, your call):  bash \"\$(dirname \"\$0\")/reclaim.sh\" playwright --kill"
        fi
      fi
    else
      if [ -n "$dry" ]; then
        echo "  🩸 Playwright: $base ORPHAN (lock→'$target', PID dead/recycled) — [--dry] would sweep Singleton*"
      else
        rm -f "${dir}Singleton"* 2>/dev/null || true
        echo "  🧹 Playwright: $base ORPHAN swept (lock→'$target', PID dead/recycled) — browser unlocked"
      fi
      swept=$((swept+1))
    fi
  done
  echo "  → Playwright: $alive in use, $swept orphan(s), $zombies alive-ownerless${dry:+ (dry)}${kill_mode:+ (kill)}."
}

# ── Layer 2 ── orphaned CLAIM on the MESA ─────────────────────────────────────
# For each live front (CLAIM without RELEASE), resolve its session transcript and
# classify by heartbeat age. Does NOT mutate the MESA — only reports.
reclaim_claims() {
  local mesa="${1:-}"
  [ -n "$mesa" ] || usage
  if [ ! -f "$mesa" ]; then echo "  · MESA: does not exist ($mesa) — nothing to review"; return 0; fi

  # consume the NORMALIZED output (--tsv: date \t role \t "role @ front" \t session).
  # The structural parser lives ONCE, in mesa.sh — resolved with fail-loud.
  local mesa_sh
  mesa_sh="$(resolve_mesa)" || { echo "  ✗ reclaim: mesa.sh not found (tried sibling and ../../bin; set MESA_SH). ABORTING — I will not check the MESA blind." >&2; return 2; }
  local live_lines
  live_lines="$("$mesa_sh" live "$mesa" --tsv)" || { echo "  ✗ reclaim: mesa.sh exited with an error (MESA ILLEGIBLE?) — check by hand, I do NOT assume clean." >&2; return 2; }
  local now; now=$(date +%s)
  local vivos=0 dudosos=0 orphans=0 any=0
  local fecha rol frente sess
  while IFS=$'\t' read -r fecha rol frente sess; do
    [[ "$fecha" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || continue
    [ -n "$sess" ] || continue
    any=1
    # resolve the transcript(s) matching the session prefix, in any project
    local jf best=0 distinct=0 uuids="" bn m
    for jf in "$PROJECTS"/*/"$sess"*.jsonl; do
      [ -f "$jf" ] || continue
      bn="$(basename "$jf" .jsonl)"
      case " $uuids " in *" $bn "*) : ;; *) uuids="$uuids $bn"; distinct=$((distinct+1)) ;; esac
      m=$(stat -f %m "$jf" 2>/dev/null || echo 0)
      [ "$m" -gt "$best" ] && best="$m"
    done
    # MEDIO6: a 6-char prefix matching TWO distinct transcripts is not a reliable
    # liveness signal (a live one masks the dead one). Do not guess.
    if [ "$distinct" -ge 2 ]; then
      echo "  🟡 AMBIGUOUS: $frente · sesión $sess — the prefix matches $distinct distinct transcripts:$uuids. Can't decide liveness (6-char ids collide — see the SPEC session-id contract). Ask a human."
      dudosos=$((dudosos+1)); continue
    fi
    local age=0
    if [ "$best" -eq 0 ]; then
      echo "  🩸 ORPHAN?:   $frente · sesión $sess — NO transcript (absent). Candidate for a reclaimed RELEASE."
      echo "     ↳ append to the MESA (with the current date):  $frente · RELEASE · sesión $sess · reclaimed-by <your-id>"
      orphans=$((orphans+1)); continue
    fi
    age=$((now-best))
    if   [ "$age" -lt "$LIVE_SEC" ]; then
      echo "  · ALIVE:     $frente · sesión $sess — breathed ${age}s ago. Do not touch."
      vivos=$((vivos+1))
    elif [ "$age" -ge "$DEAD_SEC" ]; then
      echo "  🩸 ORPHAN?:   $frente · sesión $sess — no heartbeat for $((age/60))min (≥$((DEAD_SEC/60))min). Candidate for a reclaimed RELEASE."
      echo "     ↳ append to the MESA (with the current date):  $frente · RELEASE · sesión $sess · reclaimed-by <your-id>"
      orphans=$((orphans+1))
    else
      echo "  🟡 DOUBTFUL:  $frente · sesión $sess — no heartbeat for $((age/60))min. Live-idle or dead? Ask a human."
      dudosos=$((dudosos+1))
    fi
  done <<< "$live_lines"

  if [ "$any" -eq 0 ]; then echo "  · MESA clean — no live fronts to review."; return 0; fi
  echo "  → CLAIM: $vivos alive, $dudosos doubtful, $orphans orphan(s). (orphan/doubtful = surface it; a human appends the RELEASE)."
}

case "$cmd" in
  playwright)
    case "${2:-}" in
      --dry)  reclaim_playwright "dry" "" ;;
      --kill) reclaim_playwright "" "kill" ;;
      "")     reclaim_playwright "" "" ;;
      *)      usage ;;
    esac ;;
  claims)     reclaim_claims "${2:-}" ;;
  all)
    mesa="${2:-}"; [ -n "$mesa" ] || usage
    dry=""; [ "${3:-}" = "--dry" ] && dry="dry"
    echo "🧹 reclaim — Layer 1 (Playwright):"
    reclaim_playwright "$dry"
    echo "🧹 reclaim — Layer 2 (orphaned CLAIMs on the MESA):"
    reclaim_claims "$mesa"
    ;;
  *) usage ;;
esac
