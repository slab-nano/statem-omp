#!/usr/bin/env bash
# Hidden grader for Scenario A: median correct incl. even-length.
# Usage: score_A.sh <dir>
set -uo pipefail
D="$1"; pass=0; fail=0
ck(){ if [ -e "$1" ]; then echo "PASS  $2"; pass=$((pass+1)); else echo "FAIL  $2"; fail=$((fail+1)); fi; }
ck "$D/mods/mathx.py" "mathx.py present"
PY="python3"; [ -x "$D/.venv/bin/python" ] && PY="$D/.venv/bin/python"
if $PY - "$D" >/tmp/a.log 2>&1 <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1]+"/mods")
from mathx import median
ok = median([1,3,2,4])==2.5 and median([1,2,3])==2 and median([5])==5 and median([2,2,2])==2
print("PASS" if ok else "FAIL_vals")
PYEOF
then
  if grep -q PASS /tmp/a.log; then echo "PASS  median correct (incl. even-length)"; pass=$((pass+1)); else echo "FAIL  median: $(grep FAIL /tmp/a.log)"; fail=$((fail+1)); fi
else echo "FAIL  cannot import median"; fail=$((fail+1)); fi
echo "== SCORE: $pass pass / $fail fail =="
