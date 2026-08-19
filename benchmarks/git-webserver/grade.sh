#!/usr/bin/env bash
# Official-style grader for the git-webserver task.
# Does a FRESH consumer path: clone, write hello.html, commit, push origin master,
# then curl the deployed page. PASS iff curl returns exactly "hello world".
# Usage: grade.sh <sandbox> <port>
set -uo pipefail
SB="$1"; PORT="${2:-8080}"
CK="/tmp/gw_grade_work_$(date +%s)_$RANDOM"
rm -rf "$CK"; mkdir -p "$CK"
echo "== grading consumer path (fresh clone/push/curl) =="
git clone -q "$SB/git/server.git" "$CK/repo" 2>&1 | sed 's/^/  /'
cd "$CK/repo"
printf 'hello world\n' > hello.html
git add hello.html
git -c user.email=grader@tb -c user.name=grader commit -qm "grade: add hello.html"
if ! git push -q origin HEAD:master 2>"$CK/pusherr"; then
  echo "FAIL  push failed: $(tail -1 "$CK/pusherr")"
  rm -rf "$CK"; exit 1
fi
sleep 0.6
BODY="$(curl -s --max-time 5 "http://localhost:$PORT/hello.html")"
if [ "$BODY" = "hello world" ]; then
  echo "PASS  curl :$PORT/hello.html == 'hello world'"
  rm -rf "$CK"; exit 0
else
  echo "FAIL  curl returned [${BODY:-<empty>}]"
  # surface likely cause
  curl -s --max-time 3 -o /dev/null -w '  HTTP %{http_code}\n' "http://localhost:$PORT/hello.html" 2>/dev/null || echo "  (no server reachable on :$PORT)"
  rm -rf "$CK"; exit 1
fi
