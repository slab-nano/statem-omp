#!/usr/bin/env bash
# Parallel sub-agent experiment: the 4-module sats package, leaves done in parallel.
# 4 concurrent omp agents each implement ONE independent module, then a coordinator
# writes __init__ + verify.py and runs the verify gate.
# Compare wall-clock against sequential (scenario 9 D/baseline ~107s; statem-sequential ~230s).
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
DIR="/tmp/sats_parallel"; LOGDIR="/tmp/sats_parallel_logs"
rm -rf "$DIR" "$LOGDIR"; mkdir -p "$DIR" "$LOGDIR"

declare -A MOD
MOD[framer]='framer.py: deframe(packets: list[bytes]) -> list[bytes] (filter empty byte objects); reassemble(frames: list[bytes]) -> bytes (b"".join(frames)); check_crc(block: bytes) -> bool (sum(block) % 2 == 0); extract_telemetry(block: bytes) -> bytes (block[4:]); sequence_ok(seq: list[int]) -> bool (strictly consecutive ascending)'
MOD[link]='link.py: compute_link_budget(ptx, grx, freq, dist) -> float (ptx + grx - 20*log10(dist)); snr_to_ber(snr) -> float (10**(-snr/10)); bandwidth_efficiency(mod_order, coderate) -> float (mod_order*coderate); doppler_shift(freq, vel) -> float (freq*vel/299792458.0); propagation_delay(dist) -> float (dist/299792458.0)'
MOD[eph]='eph.py: mean_anomaly(raan, inc, t) -> float (raan + inc*t); orbital_period(sma) -> float (2*pi*sqrt(sma**3/398600.4418)); eccentric_anomaly(e, m) -> float (m + e*sin(m)); true_anomaly(e, E) -> float (2*atan2(sqrt(1+e)*sin(E/2), sqrt(1-e)*cos(E/2))); ground_track_speed(alt) -> float (2*pi*(6371.0+alt)/86400.0)'
MOD[decoder]='decoder.py: parse_packet(blob) -> dict ({"len": len(blob), "id": blob[0]}); decode_telemetry(data) -> list[int] (list(data)); extract_health(telem) -> str (str(telem.get("health","OK"))); checksum_valid(pkt) -> bool (sum(pkt) % 256 == 0); deserialize_field(buf, offset) -> int (buf[offset])'

echo "=== launching 4 parallel sub-agents $(date -u +%H:%M:%S) ==="
T0=$(date +%s)
for m in framer link eph decoder; do
  omp -p "Working directory: $DIR. Implement the Python module at $DIR/${m}.py with EXACTLY these functions and behavior: ${MOD[$m]}. Do NOT create any other files. Verify it imports and behaves correctly, then report a one-line summary." --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/${m}.log" 2>&1 &
done
wait
T1=$(date +%s)
echo "=== 4 parallel sub-agents done, elapsed=$((T1-T0))s ==="
for m in framer link eph decoder; do echo "--- $m: $(tail -1 "$LOGDIR/${m}.log" 2>/dev/null)"; done

echo "=== coordinator $(date -u +%H:%M:%S) ==="
T2=$(date +%s)
omp -p "Working directory: $DIR. The files framer.py, link.py, eph.py, decoder.py exist here. Write __init__.py that re-exports all 20 functions, and write verify.py that imports all 20 functions from these four modules and asserts them against concrete expected values. Run python3 verify.py until it passes. Report one line." --no-session --model deepseek/deepseek-v4-flash > "$LOGDIR/coord.log" 2>&1
T3=$(date +%s)
echo "=== coordinator done, elapsed=$((T3-T2))s ==="; tail -2 "$LOGDIR/coord.log"
echo "=== TOTAL parallel wall-clock = $((T3-T0))s ==="
