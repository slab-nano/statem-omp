#!/usr/bin/env bash
# Scenario B: verify-gate repair loop. Single session.
# Usage: run_B.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
DIR="/tmp/b_$MODE"
LOGDIR="/tmp/b_logs_$MODE"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

TASK='Working directory: %DIR%
Implement a Python module cal.py in %DIR% with this function:
  weekdays_between(a, b) -> int
    Returns the number of weekdays (Monday-Friday) between dates a and b, inclusive of both endpoints.
Write a quick self-check that exercises it, run it, and confirm the result is correct.
When done, report a one-line summary. Do not add unrelated files.'

STATEM_TASK='Manage this with a statem state-machine runbook (statem skill loaded). Create %DIR%/statem.yaml with nodes: plan, implement, verify, done (edges in order). On the verify node add a before_transfer command gate that runs a Python verify script which calls cal.weekdays_between with ISO STRING date inputs and asserts exact counts: ("2026-01-05","2026-01-09") == 5, ("2026-08-17","2026-08-21") == 5, ("2026-01-05","2026-01-06") == 2. The gate must pass (exit 0) before you may leave the verify node. Start the run: statem start statem.yaml --run-id b --json. After implementing cal.py, run statem save --run-id b --json then statem goto verify --run-id b --yes --json; if the gate fails, stay in verify, fix cal.py so it accepts string inputs, and retry until the gate passes. Then do the work:
'"$TASK"

if [ "$MODE" = "statem" ]; then PROMPT="$STATEM_TASK"; else PROMPT="$TASK"; fi
PROMPT="${PROMPT//%DIR%/$DIR}"

echo "=== [B/$MODE] $(date -u +%H:%M:%S) ==="
cd "$DIR"; T0=$(date +%s)
omp -p "$PROMPT" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/omp.log" 2>&1
T1=$(date +%s)
echo "=== [B/$MODE] done, elapsed=$((T1-T0))s ==="; tail -3 "$LOGDIR/omp.log"
