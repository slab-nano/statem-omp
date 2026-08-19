#!/usr/bin/env bash
# Scenario D: 3-session resume (two context wipes). Same non-inferable sats API as scenario 5.
# Session 1: framer+link (park at eph). Session 2: eph+decoder (park at verify). Session 3: verify+docs+done.
#   statem: runbook persists the exact contract across both wipes.
#   baseline: loses the contract each wipe -> drifts -> fails grader.
# Usage: run_D.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
DIR="/tmp/d_$MODE"; LOGDIR="/tmp/d_logs_$MODE"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

C='Working directory: %DIR%
You are building a Python package sats/ for satellite downlink telemetry. This is SESSION 1 of THREE.
EXACT CONTRACT (implement precisely, exact names):
Module 1 sats/framer.py: deframe(packets)->list[bytes] (filter empties), reassemble(frames)->bytes (join), check_crc(block)->bool (sum%2==0), extract_telemetry(block)->bytes (block[4:]), sequence_ok(seq)->bool (strictly consecutive ascending)
Module 2 sats/link.py: compute_link_budget(ptx,grx,freq,dist)->float (ptx+grx-20*log10(dist)), snr_to_ber(snr)->float (10**(-snr/10)), bandwidth_efficiency(m,c)->float (m*c), doppler_shift(f,vel)->float (f*vel/299792458.0), propagation_delay(dist)->float (dist/299792458.0)
Module 3 sats/eph.py: mean_anomaly(raan,inc,t)->float (raan+inc*t), orbital_period(sma)->float (2*pi*sqrt(sma**3/398600.4418)), eccentric_anomaly(e,m)->float (m+e*sin(m)), true_anomaly(e,E)->float (2*atan2(sqrt(1+e)*sin(E/2),sqrt(1-e)*cos(E/2))), ground_track_speed(alt)->float (2*pi*(6371.0+alt)/86400.0)
Module 4 sats/decoder.py: parse_packet(blob)->dict ({"len":len(blob),"id":blob[0]}), decode_telemetry(data)->list[int] (list(data)), extract_health(telem)->str (str(telem.get("health","OK"))), checksum_valid(pkt)->bool (sum(pkt)%256==0), deserialize_field(buf,off)->int (buf[off])
SESSION 1 SCOPE: implement ONLY sats/framer.py, sats/link.py, sats/__init__.py exactly to contract. Verify they behave. Then STOP. Do NOT create eph.py, decoder.py, verify.py, README.md, or any notes file, and do NOT write eph/decoder requirements to any file. Their names must be recalled or carried forward; later sessions will not repeat them.
Report a one-line summary.'

S1_STATEM='Manage this with a statem state-machine runbook (statem skill loaded) at %DIR%/sats/statem.yaml, nodes: plan, framer, link, eph, decoder, verify, docs, done. CRITICAL: the eph and decoder node prompts must each list the exact function names + behavior for that module (from the contract), because future sessions rely ONLY on the runbook. Start: statem start statem.yaml --run-id d --json. After framer.py: statem save --run-id d --json then statem goto framer --run-id d --yes --json; after link.py likewise with link. Park at eph. Then do the work:
'"$C"

S2='Working directory: %DIR%
SESSION 2. Continue the sats/ project: implement the two remaining modules (eph.py, decoder.py) exactly per the original contract, and sats/__init__.py exports. Do NOT write a README or verify.py yet. Then STOP. Report one line.'
S2_STATEM='Working directory: %DIR%
SESSION 2. Continue the sats/ project using the statem runbook at %DIR%/sats/statem.yaml (statem skill loaded). Run statem cur --run-id d --json and statem history --run-id d --tail 6 --json. The eph and decoder node prompts contain the exact contract — implement both modules per them, then statem save --run-id d --json and statem goto decoder --run-id d --yes --json (then eph already done). Park at verify. Do NOT write README/verify yet. Then do the work:
'"$S2"

S3='Working directory: %DIR%
SESSION 3 (final). Complete the sats/ project: write sats/verify.py that imports and asserts ALL 20 functions across all four modules against concrete expected values, make it pass, and write sats/README.md. Report one line.'
S3_STATEM='Working directory: %DIR%
SESSION 3 (final). Complete the sats/ project using the statem runbook at %DIR%/sats/statem.yaml (statem skill loaded). Run statem cur --run-id d --json. Finish the remaining nodes (verify, docs, done): add a before_transfer command gate on verify that runs sats/verify.py (all 20 functions asserted) and must pass, then statem save --run-id d --json and statem goto done --run-id d --yes --json. Write README.md. Then do the work:
'"$S3"

if [ "$MODE" = "statem" ]; then P1="$S1_STATEM"; P2="$S2_STATEM"; P3="$S3_STATEM"; else P1="$C"; P2="$S2"; P3="$S3"; fi
for i in P1 P2 P3; do declare -n p=$i; p="${p//%DIR%/$DIR}"; done

echo "=== [D/$MODE] S1 $(date -u +%H:%M:%S) ==="
cd "$DIR"; T=$(date +%s); omp -p "$P1" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s1.log" 2>&1; echo "S1 $(( $(date +%s)-T ))s"; tail -2 "$LOGDIR/s1.log"
echo "=== [D/$MODE] S2 (wiped) ==="
T=$(date +%s); omp -p "$P2" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s2.log" 2>&1; echo "S2 $(( $(date +%s)-T ))s"; tail -2 "$LOGDIR/s2.log"
echo "=== [D/$MODE] S3 (wiped) ==="
T=$(date +%s); omp -p "$P3" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s3.log" 2>&1; echo "S3 $(( $(date +%s)-T ))s"; tail -2 "$LOGDIR/s3.log"
