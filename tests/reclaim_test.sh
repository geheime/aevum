#!/usr/bin/env bash
# reclaim_test.sh — regression suite for adapters/claude-code/reclaim.sh (Capa 2).
# Each case is a red-team failure mode. Run:  bash tests/reclaim_test.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RECLAIM="$DIR/../adapters/claude-code/reclaim.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check()  { if grep -qF -- "$2" <<<"$3"; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1"; echo "      want substr: $2"; echo "      got: ${3//$'\n'/ | }"; fail=$((fail+1)); fi; }
refute() { if grep -qF -- "$2" <<<"$3"; then echo "  ✗ $1 (forbidden '$2' appeared)"; echo "      got: ${3//$'\n'/ | }"; fail=$((fail+1)); else echo "  ✓ $1"; pass=$((pass+1)); fi; }

# 1 · CRIT1 — reclaim lives in adapters/claude-code/, roundtable.sh in bin/ (NOT siblings).
#     It must still resolve the parser and SEE the live front — never silently "round table clean".
mkdir -p "$TMP/proj_a"
cat > "$TMP/rt1" <<'EOF'
# round table
2026-09-14 10:00 · dev @ deploy prod · CLAIM · sesión dead01 · start
EOF
o=$(RECLAIM_PROJECTS="$TMP/proj_a" bash "$RECLAIM" claims "$TMP/rt1" 2>&1)
refute "CRIT1: not a silent false-clean" "round table clean" "$o"
check  "CRIT1: sees the orphan front"    "dev @ deploy prod" "$o"

# 2 · ALTO5/H7 — reclaim must EMIT a ready-to-copy RELEASE with the dead's exact
#     role @ front + dead session, so the human never composes the key by hand.
check "ALTO5: emits exact RELEASE line" "dev @ deploy prod · RELEASE · sesión dead01" "$o"

# 3 · MEDIO6 — a 6-char session prefix that matches TWO distinct transcripts must
#     not be trusted as one liveness signal; report ambiguity, don't mask an orphan.
mkdir -p "$TMP/proj_b/slug1"
: > "$TMP/proj_b/slug1/a1b2c3d4e5f6.jsonl"
: > "$TMP/proj_b/slug1/a1b2c399887766.jsonl"
cat > "$TMP/rt2" <<'EOF'
# round table
2026-09-14 10:00 · dev @ deploy · CLAIM · sesión a1b2c3 · start
EOF
o2=$(RECLAIM_PROJECTS="$TMP/proj_b" bash "$RECLAIM" claims "$TMP/rt2" 2>&1)
check  "MEDIO6: flags prefix ambiguity" "AMBIGU" "$o2"
refute "MEDIO6: does not claim ALIVE"   "ALIVE" "$o2"

echo ""; echo "  → $pass passed, $fail failed"
[ "$fail" -eq 0 ]
