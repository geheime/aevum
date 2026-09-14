#!/usr/bin/env bash
# mesa_test.sh — regression suite for bin/mesa.sh.
# Every case below is a failure mode a red team reproduced against the parser.
# Run:  bash tests/mesa_test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
MESA="$DIR/../bin/mesa.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

check()  { if grep -qF -- "$2" <<<"$3"; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1"; echo "      want substr: $2"; echo "      got:        ${3//$'\n'/ | }"; fail=$((fail+1)); fi; }
refute() { if grep -qF -- "$2" <<<"$3"; then echo "  ✗ $1 (forbidden '$2' appeared)"; echo "      got: ${3//$'\n'/ | }"; fail=$((fail+1)); else echo "  ✓ $1"; pass=$((pass+1)); fi; }

# 1 · happy path — an open CLAIM is a live front
cat > "$TMP/t1" <<'EOF'
# MESA
2026-09-14 10:00 · dev @ deploy · CLAIM · sesión abc123 · start
EOF
o=$("$MESA" live "$TMP/t1"); check "happy: live front shows" "dev @ deploy" "$o"

# 2 · CLAIM then RELEASE (same key) — clean
cat > "$TMP/t2" <<'EOF'
# MESA
2026-09-14 10:00 · dev @ deploy · CLAIM   · sesión abc123 · start
2026-09-14 12:00 · dev @ deploy · RELEASE · sesión abc123 · done
EOF
o=$("$MESA" live "$TMP/t2"); check "claim+release: clean" "0 live fronts" "$o"

# 3 · CRIT2 — a front containing a bare keyword must not hijack the event.
#     front = "review · CLAIM"; the RELEASE must close it → net clean.
cat > "$TMP/t3" <<'EOF'
# MESA
2026-09-14 10:00 · dev @ review · CLAIM · CLAIM · sesión abc123 · start
2026-09-14 12:00 · dev @ review · CLAIM · RELEASE · sesión abc123 · done
EOF
o=$("$MESA" live "$TMP/t3")
check  "CRIT2: keyword-in-front closes clean" "0 live fronts" "$o"
refute "CRIT2: no zombie live front"          "review · CLAIM · CLAIM" "$o"

# 4 · ALTO3 — a partially malformed date-line must be reported, not dropped silently,
#     and the valid front alongside it must still surface.
cat > "$TMP/t4" <<'EOF'
# MESA
2026-09-14 10:00 · dev @ deploy · CLAIM · sesión abc123 · start
2026-09-14 11:00 · dev @ build · CLAIM
EOF
o=$("$MESA" live "$TMP/t4")
check "ALTO3: valid front still shows" "dev @ deploy" "$o"
check "ALTO3: malformed line is flagged" "ignored" "$o"

# 5 · original promise — a front with a NON-keyword ' · ' segment parses whole
cat > "$TMP/t5" <<'EOF'
# MESA
2026-09-14 10:00 · cto @ web pre-live · lista + FAQ · CLAIM · sesión xyz789 · go
EOF
o=$("$MESA" live "$TMP/t5"); check "sep-in-front: full front preserved" "web pre-live · lista + FAQ" "$o"

echo ""; echo "  → $pass passed, $fail failed"
[ "$fail" -eq 0 ]
