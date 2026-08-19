#!/usr/bin/env bash
# Two-session resume scenario: baseline vs statem.
# Session 1 builds fin/ledger.py + fin/ratios.py + fin/SPEC.md and STOPS.
# Session 2 (blank conversation = context wipe) must continue to completion.
# A strict hidden grader checks all 20 functions across all 4 modules.
# Usage: run_fin.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
DIR="/tmp/fin_$MODE"
LOGDIR="/tmp/fin_logs_$MODE"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

FULL_SPEC='Working directory: %DIR%
You are building a multi-module Python financial library `fin/`. This is SESSION 1 of a two-session build.
EXACT CONTRACT (implement precisely):
Module 1 fin/ledger.py:
  credit(entries, amount) -> append ("credit", amount) to the list entries in place; return entries
  debit(entries, amount) -> append ("debit", amount); return entries
  balance(entries) -> sum(amount for kind=="credit") - sum(amount for kind=="debit")
  total_credits(entries) -> sum of credit amounts
  total_debits(entries) -> sum of debit amounts
Module 2 fin/ratios.py (all return float):
  current_ratio(assets, liab) -> assets/liab
  quick_ratio(assets, inventory, liab) -> (assets-inventory)/liab
  debt_equity(debt, equity) -> debt/equity
  gross_margin(revenue, cogs) -> (revenue-cogs)/revenue
  roa(net_income, assets) -> net_income/assets
SESSION 1 SCOPE: implement ONLY fin/ledger.py, fin/ratios.py, and fin/__init__.py exactly to the contract above. Then write %DIR%/fin/SPEC.md documenting the FULL contract for ALL FOUR modules (including modules 3 and 4 below, which a later session will implement). Verify fin/ledger.py and fin/ratios.py import and behave correctly. Then STOP. Do NOT create forecast.py, sched.py, verify.py, or README.md in this session.
Remaining modules (document in SPEC.md ONLY; do NOT implement in session 1):
Module 3 fin/forecast.py: cagr(start,end,periods), future_value(pv,rate,n), present_value(fv,rate,n), simple_interest(principal,time,rate), compound_interest(principal,rate,n)
Module 4 fin/sched.py: days_between(a,b), business_days(a,b), month_label(year,month), is_leap(year), quarters_between(a,b)
Stop after session 1 scope is complete. Report a one-line summary.'

STATEM_S1='Manage this with a statem state-machine runbook (statem skill loaded). Create %DIR%/fin/statem.yaml with nodes: plan, ledger, ratios, forecast, sched, verify, docs, done (edges in that order). Start the run with `statem start statem.yaml --run-id fin --json` from %DIR%/fin. After finishing ledger.py run `statem save --run-id fin --json` then `statem goto ledger --run-id fin --yes --json`; after ratios.py run `statem save --run-id fin --json` then `statem goto ratios --run-id fin --yes --json`. Leave the runbook pointed at the node where session 2 should resume. Then do the work:
'"$FULL_SPEC"

RESUME_BASE='Working directory: %DIR%
Continue the `fin/` library project to completion. A prior session set up fin/ledger.py, fin/ratios.py, fin/__init__.py and %DIR%/fin/SPEC.md. Read %DIR%/fin/SPEC.md and the existing code, then finish the project: implement the remaining modules (forecast.py, sched.py) per the contract, write %DIR%/fin/verify.py that imports and asserts ALL functions from ALL FOUR modules against concrete expected values, make it pass, and write %DIR%/fin/README.md. All 20 functions across all four modules must be correct.'

RESUME_STATEM='Working directory: %DIR%
Continue the `fin/` library project using the statem runbook at %DIR%/fin/statem.yaml (statem skill loaded). First run `statem cur --run-id fin --json` and `statem history --run-id fin --tail 10 --json` to see where the run is. Follow the runbook to complete the remaining nodes (forecast, sched, verify, docs, done), using `statem save --run-id fin --json` then `statem goto <next> --run-id fin --yes --json` after each. On the verify node add a before_transfer command gate that runs the verify.py assertions so you cannot leave it until they pass. Then do the work:
'"$RESUME_BASE"

if [ "$MODE" = "statem" ]; then S1="$STATEM_S1"; S2="$RESUME_STATEM"; else S1="$FULL_SPEC"; S2="$RESUME_BASE"; fi
S1="${S1//%DIR%/$DIR}"; S2="${S2//%DIR%/$DIR}"

echo "=== [fin/$MODE] SESSION 1 $(date -u +%H:%M:%S) ==="
S1_START=$(date +%s)
cd "$DIR"
omp -p "$S1" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s1.log" 2>&1
S1_END=$(date +%s)
echo "=== [fin/$MODE] S1 done, elapsed=$((S1_END-S1_START))s ==="
tail -3 "$LOGDIR/s1.log"
echo "--- after S1, files present ---"
find "$DIR/fin" -maxdepth 1 -type f 2>/dev/null | xargs -n1 basename 2>/dev/null | sort
echo "=== [fin/$MODE] SESSION 2 (context wiped) $(date -u +%H:%M:%S) ==="
S2_START=$(date +%s)
omp -p "$S2" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s2.log" 2>&1
S2_END=$(date +%s)
echo "=== [fin/$MODE] S2 done, elapsed=$((S2_END-S2_START))s ==="
tail -3 "$LOGDIR/s2.log"
echo "--- after S2, files present ---"
find "$DIR/fin" -maxdepth 1 -type f 2>/dev/null | xargs -n1 basename 2>/dev/null | sort
