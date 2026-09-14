#!/usr/bin/env bash
# baton_cas_test.sh — the CAS closes the concurrent same-role baton clobber
# (red-team ALTO4 / "deuda del paralelo real"). Run: bash tests/baton_cas_test.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CAS="$DIR/../bin/baton-cas.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if grep -qF -- "$2" <<<"$3"; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1"; echo "     want: $2"; echo "     got: ${3//$'\n'/ | }"; fail=$((fail+1)); fi; }
eq()    { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1 (want '$2' got '$3')"; fail=$((fail+1)); fi; }

B="$TMP/_BATON_dev.md"

# 1 · sha of an absent baton = NONE (the founding sentinel)
eq "sha absent = NONE" "NONE" "$(bash "$CAS" sha "$B")"

# 2 · founding write (expected NONE) lands
echo "gen 1 testimony" | bash "$CAS" write "$B" NONE >/dev/null
eq "founding write lands" "gen 1 testimony" "$(cat "$B")"

# 3 · normal write with the correct prior sha lands
s1="$(bash "$CAS" sha "$B")"
echo "gen 2 testimony" | bash "$CAS" write "$B" "$s1" >/dev/null
eq "CAS write lands" "gen 2 testimony" "$(cat "$B")"

# 4 · THE clobber: A booted at gen-2 sha; B closes first (gen 3); A's close must
#     be REJECTED and must NOT overwrite B — the generation is preserved.
s_boot="$(bash "$CAS" sha "$B")"                                   # A's boot-time sha (gen 2)
echo "B wrote gen 3"                    | bash "$CAS" write "$B" "$s_boot" >/dev/null   # B closes first
out=$(echo "A tries to overwrite gen 3" | bash "$CAS" write "$B" "$s_boot" 2>&1); rc=$?
check "concurrent: conflict flagged" "CONFLICT" "$out"
eq    "concurrent: B's testimony survives" "B wrote gen 3" "$(cat "$B")"
if [ "$rc" -ne 0 ]; then echo "  ✓ concurrent: nonzero exit"; pass=$((pass+1)); else echo "  ✗ concurrent: expected nonzero exit"; fail=$((fail+1)); fi

# 5 · founding race: expected NONE but someone already founded the seat
B2="$TMP/_BATON_pm.md"
echo "founder A" | bash "$CAS" write "$B2" NONE >/dev/null
out=$(echo "founder B" | bash "$CAS" write "$B2" NONE 2>&1) || true
check "founding race: conflict flagged" "CONFLICT" "$out"
eq    "founding race: no clobber" "founder A" "$(cat "$B2")"

echo ""; echo "  → $pass passed, $fail failed"
[ "$fail" -eq 0 ]
