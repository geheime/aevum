#!/usr/bin/env bash
# mesa.sh — the MESA parser (live fronts + the 409 check).
#
# WHY THIS IS A SCRIPT (do not re-inline it into the ritual text): the parser
#   once lived embedded in the /boot and /close markdown. Its awk field refs
#   ($0 $2 $3 $4) COLLIDE with a host command's positional-argument substitution
#   ($1, $2, …): a boot with a multi-word argument replaces each awk $N with the
#   Nth word of the arg → awk becomes `ev=<word>` → never matches CLAIM → prints
#   "clean" WHILE LYING. Production bug 2026-07-17 (a false-clean with a live
#   front sitting on the MESA). A real .sh has no slash-command expansion, so the
#   $N are genuine awk fields. The ritual text only CALLS this script.
#
# STRUCTURAL PARSER (2026-09-04): the event is located BY PATTERN — the keyword
#   immediately followed by the `sesión` field — not by column position. The old
#   parser assumed $3=event and $4=session; a front containing " · " (seen in
#   prod) shifted the columns → check-409 listed "sesión CLAIM" as an id and
#   `live` did NOT SEE that CLAIM (a silent false-clean, same family as the
#   07-17 bug). Anchoring on the session field also stops a bare keyword inside a
#   front from hijacking the event slot.
#
# BOUNDED 409: check-409 lists only same-role events AFTER your own CLAIM. It
#   once listed every session of the role that had ever written ("last writer"):
#   fine with 3 sessions, pure noise with 90 (a role on a busy house got 36
#   spurious risk flags when the answer was "all clear"). A RELEASE earlier than
#   your CLAIM already wrote its baton before you read it — that is the baton you
#   inherited, not a 409. If it cannot find your CLAIM it does NOT infer: it
#   warns and falls back to the full list (safe over-alarm, fail-loud).
#
# Fail-loud: if the MESA has data lines but 0 parseable events, it SHOUTS instead
#   of saying "clean" — a false-clean is never again mistaken for clean.
#
# Usage:
#   mesa.sh live      <MESA_FILE> [--tsv]                  # live fronts (CLAIM without RELEASE)
#                                                          #   --tsv: date \t role \t "role @ front" \t session (for reclaim.sh)
#   mesa.sh check-409 <MESA_FILE> <ROLE> <SESSION> [SINCE] # other same-role instances since your CLAIM (close)
#                                                          #   SINCE = 'YYYY-MM-DD HH:MM' forces the bound (tests / seat with no CLAIM)
#
# — Designed by Humans · Built by Intelligence

set -euo pipefail

cmd="${1:-}"
mesa="${2:-}"

usage() {
  echo "uso: mesa.sh live <MESA_FILE> [--tsv]  |  mesa.sh check-409 <MESA_FILE> <ROL> <SESION> [DESDE]" >&2
  exit 2
}

[ -n "$cmd" ] || usage

# Parser compartido. Setea P_fecha P_rol P_frente ("rol @ frente") P_ev P_ses P_nota.
# Devuelve 1 si la línea es un evento parseable, 0 si no.
# El evento se busca desde el campo 3 (1=fecha, 2=al menos el arranque del frente).
PARSE='
function parse(line,   n, f, i, t, a, nx) {
  n = split(line, f, " · ")
  if (n < 4) return 0
  P_k = 0
  # the event is the keyword IMMEDIATELY FOLLOWED by the "sesión <id>" field.
  # anchoring on the session field stops a bare keyword INSIDE the front (e.g. a
  # front review-then-CLAIM) from hijacking the event slot: the promise that a
  # front containing a bare separator never hides its CLAIM was only partial
  # (red-team CRIT2). No apostrophes in this string — it lives in single quotes.
  for (i = 3; i < n; i++) {
    t = f[i]; gsub(/^ +| +$/, "", t)
    if (t == "CLAIM" || t == "RELEASE" || t == "NOTA") {
      nx = f[i+1]; gsub(/^ +| +$/, "", nx)
      if (nx ~ /^sesión /) { P_k = i; P_ev = t; break }
    }
  }
  if (!P_k) return 0
  P_fecha = f[1]; gsub(/^ +| +$/, "", P_fecha)
  # sortable, zero-padded timestamp — or it does not parse. Keeps the
  # lexicographic compare in check-409 honest (an unpadded 9:05 mis-sorts;
  # red-team MEDIO8) and feeds the ignorada count instead of a silent drop.
  if (P_fecha !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$/) return 0
  P_frente = f[2]; for (i = 3; i < P_k; i++) P_frente = P_frente " · " f[i]
  split(P_frente, a, "@"); P_rol = a[1]; gsub(/ /, "", P_rol)
  P_ses = f[P_k + 1]; gsub(/sesión /, "", P_ses); gsub(/ /, "", P_ses)
  P_nota = ""; for (i = P_k + 2; i <= n; i++) P_nota = P_nota (P_nota == "" ? "" : " · ") f[i]
  return 1
}'

case "$cmd" in
  live)
    [ -n "$mesa" ] || usage
    tsv=0; [ "${3:-}" = "--tsv" ] && tsv=1
    if [ ! -f "$mesa" ]; then
      [ "$tsv" = 1 ] || echo "(no MESA yet — serial project or first use)"
      exit 0
    fi
    awk -v tsv="$tsv" "$PARSE"'
      /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        datalines++
        if (!parse($0)) next
        key = P_frente " · " P_ses                 # key = "<role> @ <front>" + session
        if (P_ev == "CLAIM")        { open[key] = $0; tf[key] = P_fecha; tr[key] = P_rol; tfr[key] = P_frente; ts[key] = P_ses; seen++ }
        else if (P_ev == "RELEASE") { delete open[key]; seen++ }
        else                        { seen++ }   # NOTA: recognized, opens/closes nothing
      }
      END {
        if (datalines > 0 && seen == 0) {
          print "⚠ MESA ILLEGIBLE: " datalines " data line(s) but 0 parseable events."
          print "  Do NOT trust this — open the file by hand. (possible format/encoding drift)"
          exit 3
        }
        dropped = datalines - seen
        if (dropped > 0) {
          # fail-loud on PARTIAL corruption too, not only all-or-nothing: one bad
          # line among good ones used to vanish silently → invisible live front
          # → clobber/orphan (red-team ALTO3).
          if (tsv) print "⚠ " dropped " line(s) with a valid date but unparseable format — ignored; check by hand." > "/dev/stderr"
          else     print "⚠ " dropped " line(s) ignored (valid date, unparseable format) — check by hand."
        }
        n = 0
        for (k in open) {
          if (tsv) print tf[k] "\t" tr[k] "\t" tfr[k] "\t" ts[k]
          else     print open[k]
          n++
        }
        if (!n && !tsv) print "(0 live fronts — MESA clean)"
      }
    ' "$mesa"
    ;;

  check-409)
    rol="${3:-}"; me="${4:-}"; desde="${5:-}"
    { [ -n "$mesa" ] && [ -n "$rol" ] && [ -n "$me" ]; } || usage
    if [ ! -f "$mesa" ]; then
      echo "✓ no MESA — no other instance; all clear"
      exit 0
    fi
    awk -v rol="$rol" -v me="$me" -v desde="$desde" "$PARSE"'
      /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        datalines++
        if (!parse($0)) next
        events++
        # my bound = my earliest CLAIM (wider window = safer)
        if (P_ses == me && P_ev == "CLAIM" && (myclaim == "" || P_fecha < myclaim)) myclaim = P_fecha
        if (P_rol == rol && P_ses != me && P_ses != "") { n++; L[n] = P_fecha; S[n] = P_ses; F[n] = P_frente; E[n] = P_ev }
      }
      END {
        if (datalines > 0 && events == 0) {
          print "⚠ MESA ILLEGIBLE: " datalines " data line(s), 0 parsed — check by hand before writing the baton."
          exit 3
        }
        if (desde == "") desde = myclaim
        if (desde == "") {
          print "⚠ could not find your CLAIM (sesión " me ") on the MESA — no time bound: listing the ENTIRE history of your role (over-alarm). Pass SINCE as the 5th arg to bound it."
        }
        cnt = 0
        for (i = 1; i <= n; i++) {
          if (desde != "" && L[i] < desde) continue
          print "⚠ 409-risk: " L[i] " · " F[i] " · " E[i] " · sesión " S[i] " — re-read and DIFF the baton before writing"
          cnt++
        }
        if (!cnt) {
          if (desde != "") print "✓ no other instance of your role wrote to the MESA since your CLAIM (" desde ") — all clear"
          else             print "✓ no other instance of your role — all clear"
        }
      }
    ' "$mesa"
    ;;

  *) usage ;;
esac
