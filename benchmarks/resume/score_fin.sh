#!/usr/bin/env bash
# Hidden grader for the fin project. Usage: score_fin.sh <dir>
set -uo pipefail
D="$1"; F="$D/fin"; pass=0; fail=0
ck(){ if [ -e "$1" ]; then echo "PASS  $2"; pass=$((pass+1)); else echo "FAIL  $2"; fail=$((fail+1)); fi; }
echo "== deliverables =="
ck "$F/ledger.py" "ledger.py"
ck "$F/ratios.py" "ratios.py"
ck "$F/forecast.py" "forecast.py"
ck "$F/sched.py" "sched.py"
ck "$F/verify.py" "verify.py"
ck "$F/README.md" "README.md"
PY="python3"; [ -x "$D/.venv/bin/python" ] && PY="$D/.venv/bin/python"
echo "== functional (all 20) =="
if $PY -c "import sys; sys.path.insert(0,'$F'); from ledger import credit,debit,balance,total_credits,total_debits; from ratios import current_ratio,quick_ratio,debt_equity,gross_margin,roa; from forecast import cagr,future_value,present_value,simple_interest,compound_interest; from sched import days_between,business_days,month_label,is_leap,quarters_between; print('ok')" >/tmp/fi.log 2>&1; then
  echo "PASS  all 20 import"; pass=$((pass+1)); else echo "FAIL  imports: $(head -1 /tmp/fi.log)"; fail=$((fail+1)); fi
$PY - "$F" >/tmp/ff.log 2>&1 <<'PYEOF'
import sys, math
F=sys.argv[1]; sys.path.insert(0,F)
from ledger import credit,debit,balance,total_credits,total_debits
from ratios import current_ratio,quick_ratio,debt_equity,gross_margin,roa
from forecast import cagr,future_value,present_value,simple_interest,compound_interest
from sched import days_between,business_days,month_label,is_leap,quarters_between
ok=True
e=credit([],10); e=credit(e,20); e=debit(e,5)
ok &= balance(e)==25 and total_credits(e)==30 and total_debits(e)==5
ok &= current_ratio(100,50)==2.0 and quick_ratio(100,20,50)==1.6 and debt_equity(80,40)==2.0 and gross_margin(200,120)==0.4 and roa(10,50)==0.2
ok &= abs(cagr(100,200,2)-0.41421356237309515)<1e-9
ok &= future_value(100,0.1,2)==121.0 and present_value(121,0.1,2)==100.0
ok &= simple_interest(100,2,0.05)==10.0 and abs(compound_interest(100,0.1,2)-21.0)<1e-9
ok &= days_between("2026-01-01","2026-01-10")==9 and is_leap(2024) and not is_leap(2025)
ok &= month_label(2026,8)=="August" and business_days("2026-01-05","2026-01-09")==5
ok &= quarters_between("2026-01-15","2026-10-01")==3
print("PASS" if ok else "FAIL")
PYEOF
if grep -q PASS /tmp/ff.log; then echo "PASS  all 20 behaviors correct"; pass=$((pass+1)); else echo "FAIL  behavior: $(tail -1 /tmp/ff.log)"; fail=$((fail+1)); fi
if $PY "$F/verify.py" >/tmp/fv.log 2>&1 && grep -qi pass /tmp/fv.log; then
  echo "PASS  verify.py runs+passes"; pass=$((pass+1)); else echo "FAIL  verify.py: $(tail -1 /tmp/fv.log)"; fail=$((fail+1)); fi
echo "== SCORE: $pass pass / $fail fail =="
