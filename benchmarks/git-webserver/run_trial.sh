#!/usr/bin/env bash
# Run one git-webserver trial. Usage: run_trial.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
SB="/tmp/tb_gw_$MODE"
PORT=8080
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# free the port first
pkill -f "http.server $PORT" 2>/dev/null
sleep 0.5

bash "$HERE/setup_env.sh" "$SB"

CORE='Working directory: %SB%
You are configuring a git-driven web deployment on this machine (a Terminal-Bench style task). No docker; everything is local processes.

Given environment:
- An EMPTY bare git repository at: %SB%/git/server.git  (default branch: master)
- An EMPTY web root directory at: %SB%/webroot

Task: configure it so the full consumer path works end-to-end:
1. A user can `git clone %SB%/git/server.git` into a fresh work dir.
2. They write a file hello.html containing exactly: hello world, then git add hello.html, commit, and git push origin master.
3. After the push, the file appears in %SB%/webroot, served by an HTTP server on port 8080.
4. So `curl http://localhost:8080/hello.html` returns: hello world

You must implement:
- A post-receive hook in %SB%/git/server.git/hooks/ that checks out each push (at least the master branch) into %SB%/webroot. Make it executable.
- Start an HTTP server on port 8080 serving %SB%/webroot. It MUST keep running after your command returns, because a grader checks it later. Start it fully detached so it survives the shell: use `setsid nohup python3 -m http.server 8080 --directory %SB%/webroot > %SB%/server.log 2>&1 &` and then `disown` (or equivalent).
Verify it yourself with a FRESH clone + commit + push + curl before finishing. Do not commit anything to any other repository.
When done, report a one-line summary.'

if [ "$MODE" = "statem" ]; then
  TASK='Manage this work with a statem state-machine runbook (the statem skill is loaded). Write %SB%/statem.yaml with nodes: env_ready, deploy_hook, web_server, verify, done (edges in that order). On the verify node add a before_transfer command gate that runs `curl -s http://localhost:8080/hello.html` and passes only if the output equals `hello world`; the agent must not leave verify until that gate passes. Start the run with `statem start statem.yaml --run-id gw --json` (from %SB%). After each step run `statem save --run-id gw --json` then `statem goto <next> --run-id gw --yes --json`. Use `statem cur` before acting. Then do the task:
'"$CORE"
else
  TASK="$CORE"
fi
TASK="${TASK//%SB%/$SB}"

echo "=== [gw/$MODE] starting $(date -u +%H:%M:%S) ==="
start=$(date +%s)
cd "$SB"
omp -p "$TASK" --model deepseek/deepseek-v4-flash > "$SB/omp.log" 2>&1
rc=$?
end=$(date +%s)
echo "=== [gw/$MODE] omp exit=$rc elapsed=$((end-start))s ==="
echo "--- omp log tail ---"; tail -6 "$SB/omp.log"
echo "--- server alive? ---"
(curl -s --max-time 3 -o /dev/null -w 'HTTP %{http_code}\n' "http://localhost:$PORT/" 2>/dev/null || echo "no server on :$PORT") 
echo "--- grading ---"
bash "$HERE/grade.sh" "$SB" "$PORT"
GRC=$?
# stop server for next trial
pkill -f "http.server $PORT" 2>/dev/null
exit $GRC
