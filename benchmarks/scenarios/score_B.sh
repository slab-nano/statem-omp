#!/usr/bin/env bash
# Hidden grader for Scenario B. Tests weekdays_between with STRING inputs.
# Usage: score_B.sh <dir>
set -uo pipefail
D="$1"; pass=0; fail=0
PY="python3"; [ -x "$D/.venv/bin/python" ] && PY="$D/.venv/bin/python"
ck(){ if [ -e "$1" ]; then echo "PASS  $2"; pass=$((pass+1)); else echo "FAIL  $2"; fail=$((fail+1)); fi; }
ck "$D/cal.py" "cal.py present"
if $PY - "$D" >/tmp/b.log 2>&1 <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
from cal import weekdays_between
ok=True
try:
    ok &= weekdays_between("2026-01-05","2026-01-09")==5
    ok &= weekdays_between("2026-08-17","2026-08-21")==5
    ok &= weekdays_between("2026-01-05","2026-01-06")==2
    print("PASS" if ok else "FAIL_vals")
except Exception as e:
    print("FAIL_exc:", type(e).__name__, str(e))
PYEOF
then
  if grep -q PASS /tmp/b.log; then echo "PASS  string-input behavior correct"; pass=$((pass+1)); else echo "FAIL  $(grep FAIL /tmp/b.log | head -1)"; fail=$((fail+1)); fi
else
  echo "FAIL  could not import cal.py"; fail=$((fail+1))
fi
echo "== SCORE: $pass pass / $fail fail =="
