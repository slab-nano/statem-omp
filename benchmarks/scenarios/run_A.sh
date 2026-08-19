#!/usr/bin/env bash
# Scenario A: resume-with-repair. Two sessions, context wiped between.
# Subtle bug: median() is wrong for even-length lists. A strict check catches it.
#   statem session 1: runbook verify gate (with even-length check) FAILS, records failure, STOPS.
#   statem session 2: reads failed receipt, repairs median -> passes.
#   baseline: loose self-check passes in session 1; session 2 doesn't know about the bug -> ships it -> grader fails.
# Usage: run_A.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
DIR="/tmp/a_$MODE"; LOGDIR="/tmp/a_logs_$MODE"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

S1='Working directory: %DIR%
SESSION 1 of a two-session build. Implement a Python package mods/ in %DIR%:
- mods/mathx.py with function: median(nums: list[float]) -> float  (the statistical median)
- mods/__init__.py
- mods/verify.py that imports median and asserts a few values, then run it.
A later session will do the final verification. Then STOP. Report a one-line summary.'

S1_STATEM='Manage this with a statem state-machine runbook (statem skill loaded). Create %DIR%/mods/statem.yaml with nodes: plan, implement, verify, done (edges in order). On the verify node add a before_transfer command gate that runs a strict check: python3 -c "import sys; sys.path.insert(0, %DIR%/mods); from mathx import median; assert median([1,3,2,4])==2.5; assert median([1,2,3])==2; assert median([5])==5"  (note the even-length case [1,3,2,4]). Start the run: statem start statem.yaml --run-id a --json. Implement mods/, then statem save --run-id a --json, then statem goto verify --run-id a --yes --json. If the verify gate FAILS, do NOT fix it in this session: record the failure and STOP (session 2 will repair). If it PASSES, goto done. Then do the work:
'"$S1"

S2='Working directory: %DIR%
Complete the mods/ project to final state: ensure mods/verify.py passes and the package is finished and correct. Report a one-line summary.'

S2_STATEM='Working directory: %DIR%
Complete the mods/ project using the statem runbook at %DIR%/mods/statem.yaml (statem skill loaded). First run statem cur --run-id a --json and statem history --run-id a --tail 10 --json. The verify node has a strict before_transfer gate that tests median including even-length lists; if session 1 left it failing, repair mods/mathx.py so the gate passes, then statem save --run-id a --json and statem goto done --run-id a --yes --json. Then do the work:
'"$S2"

if [ "$MODE" = "statem" ]; then P1="$S1_STATEM"; P2="$S2_STATEM"; else P1="$S1"; P2="$S2"; fi
P1="${P1//%DIR%/$DIR}"; P2="${P2//%DIR%/$DIR}"

echo "=== [A/$MODE] S1 $(date -u +%H:%M:%S) ==="
cd "$DIR"; T=$(date +%s); omp -p "$P1" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s1.log" 2>&1; echo "S1 $(( $(date +%s)-T ))s"; tail -2 "$LOGDIR/s1.log"
echo "--- S1 files ---"; find "$DIR/mods" -maxdepth 1 -type f 2>/dev/null | xargs -n1 basename | sort
echo "=== [A/$MODE] S2 (context wiped) ==="
T=$(date +%s); omp -p "$P2" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s2.log" 2>&1; echo "S2 $(( $(date +%s)-T ))s"; tail -2 "$LOGDIR/s2.log"
