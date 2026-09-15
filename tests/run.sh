#!/usr/bin/env bash
# run.sh — the whole Aevum regression suite. Every test is a failure mode a red
# team reproduced against the real scripts. Run it yourself:  bash tests/run.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in roundtable_test reclaim_test baton_cas_test; do
  echo "── $t ──"
  bash "$DIR/$t.sh" || rc=1
  echo ""
done
[ "$rc" -eq 0 ] && echo "✓ ALL GREEN" || echo "✗ SOME RED"
exit "$rc"
