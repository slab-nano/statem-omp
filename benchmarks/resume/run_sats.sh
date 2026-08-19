#!/usr/bin/env bash
# Resume scenario v2: non-inferable contract survives ONLY in the statem runbook.
# Session 1 (both) gets full 20-function contract, implements 2 modules, stops.
#   baseline: does NOT persist the remaining 2 modules' requirements.
#   statem:   writes them into the runbook (which survives the wipe).
# Session 2 (context wiped, short prompt): baseline must guess -> fails exact grader;
#   statem reads the runbook -> implements correctly -> passes.
# Usage: run_sats.sh <baseline|statem>
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
MODE="$1"
DIR="/tmp/sats_$MODE"
LOGDIR="/tmp/sats_logs_$MODE"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

CONTRACT='Working directory: %DIR%
You are building a Python package `sats/` for satellite downlink telemetry. This is SESSION 1 of a two-session build.
EXACT CONTRACT — all 20 functions across 4 modules (implement precisely, exact names):
Module 1 sats/framer.py:
  deframe(packets: list[bytes]) -> list[bytes]  # filter out empty byte objects
  reassemble(frames: list[bytes]) -> bytes      # b"".join(frames)
  check_crc(block: bytes) -> bool               # sum(block) % 2 == 0
  extract_telemetry(block: bytes) -> bytes      # block[4:]
  sequence_ok(seq: list[int]) -> bool           # strictly consecutive ascending
Module 2 sats/link.py:
  compute_link_budget(ptx: float, grx: float, freq: float, dist: float) -> float  # ptx + grx - 20*log10(dist)
  snr_to_ber(snr: float) -> float               # 10**(-snr/10)
  bandwidth_efficiency(mod_order: int, coderate: float) -> float  # mod_order*coderate
  doppler_shift(freq: float, vel: float) -> float  # freq*vel/299792458.0
  propagation_delay(dist: float) -> float       # dist/299792458.0
Module 3 sats/eph.py:
  mean_anomaly(raan: float, inc: float, t: float) -> float   # raan + inc*t
  orbital_period(sma: float) -> float           # 2*pi*sqrt(sma**3/398600.4418)
  eccentric_anomaly(e: float, m: float) -> float  # m + e*sin(m)
  true_anomaly(e: float, E: float) -> float     # 2*atan2(sqrt(1+e)*sin(E/2), sqrt(1-e)*cos(E/2))
  ground_track_speed(alt: float) -> float       # 2*pi*(6371.0+alt)/86400.0
Module 4 sats/decoder.py:
  parse_packet(blob: bytes) -> dict             # {"len": len(blob), "id": blob[0]}
  decode_telemetry(data: bytes) -> list[int]    # list(data)
  extract_health(telem: dict) -> str            # str(telem.get("health","OK"))
  checksum_valid(pkt: bytes) -> bool            # sum(pkt) % 256 == 0
  deserialize_field(buf: bytes, offset: int) -> int  # buf[offset]
SESSION 1 SCOPE: implement ONLY sats/framer.py, sats/link.py, and sats/__init__.py exactly to the contract. Verify they import and behave. Then STOP.
Do NOT create eph.py, decoder.py, verify.py, README.md, SPEC.md, or any notes file. Do NOT write the eph/decoder requirements to any file on disk. The remaining two modules (eph.py, decoder.py) will be completed in session 2, whose prompt will not repeat their function names — they must be recalled or carried forward.
Report a one-line summary.'

STATEM_S1='Manage this with a statem state-machine runbook (statem skill loaded) at %DIR%/sats/statem.yaml with nodes: plan, framer, link, eph, decoder, verify, docs, done (edges in order). CRITICAL: the runbook node prompts for eph and decoder must each list the exact function names + behavior for that module (copy them from the contract), because a future session will rely ONLY on the runbook to know what to implement. Start the run: `statem start statem.yaml --run-id sat --json`. After implementing framer.py run `statem save --run-id sat --json` then `statem goto framer --run-id sat --yes --json`; after link.py do the same with link. Park the runbook at eph. Then do the work:
'"$CONTRACT"

RESUME='Working directory: %DIR%
Continue the `sats/` satellite telemetry project to completion. A prior session implemented sats/framer.py, sats/link.py, sats/__init__.py and then stopped. Finish the project: implement the two remaining modules and the rest of the workflow so the package is complete and correct.'

RESUME_STATEM='Working directory: %DIR%
Continue the `sats/` satellite telemetry project using the statem runbook at %DIR%/sats/statem.yaml (statem skill loaded). First run `statem cur --run-id sat --json` and `statem history --run-id sat --tail 10 --json` to see where the run is. The runbook node prompts contain the exact requirements for the remaining modules — follow them. Complete the remaining nodes (eph, decoder, verify, docs, done) with `statem save --run-id sat --json` then `statem goto <next> --run-id sat --yes --json` after each. On the verify node add a before_transfer command gate running a verify.py that imports and asserts ALL 20 functions; you must not leave verify until it passes. Then do the work:
'"$RESUME"

if [ "$MODE" = "statem" ]; then S1="$STATEM_S1"; S2="$RESUME_STATEM"; else S1="$CONTRACT"; S2="$RESUME"; fi
S1="${S1//%DIR%/$DIR}"; S2="${S2//%DIR%/$DIR}"

echo "=== [sats/$MODE] SESSION 1 $(date -u +%H:%M:%S) ==="
cd "$DIR"
S1T=$(date +%s); omp -p "$S1" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s1.log" 2>&1; S1E=$(date +%s)
echo "=== [sats/$MODE] S1 done, elapsed=$((S1E-S1T))s ==="; tail -3 "$LOGDIR/s1.log"
echo "--- S1 files ---"; find "$DIR/sats" -maxdepth 1 -type f 2>/dev/null | xargs -n1 basename | sort
echo "=== [sats/$MODE] SESSION 2 (context wiped) $(date -u +%H:%M:%S) ==="
S2T=$(date +%s); omp -p "$S2" --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/s2.log" 2>&1; S2E=$(date +%s)
echo "=== [sats/$MODE] S2 done, elapsed=$((S2E-S2T))s ==="; tail -3 "$LOGDIR/s2.log"
echo "--- S2 files ---"; find "$DIR/sats" -maxdepth 1 -type f 2>/dev/null | xargs -n1 basename | sort
