#!/usr/bin/env bash
# Clean actual-token comparison: same 4-module sats task, three execution modes.
# sequential (1 agent), statem-sequential (1 agent + runbook), parallel (4 sub-agents + coordinator).
# Reads omp session files for ACTUAL input/output tokens per mode.
# Usage: run_comp.sh
set -uo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
SESS="$HOME/.omp/agent/sessions"

mkdir -p /tmp/comp_seq /tmp/comp_statem /tmp/comp_parallel

FULL='Working directory: %DIR%. Build a Python package sats/ (a satellite telemetry library) with exactly these 4 modules:
framer.py: deframe(packets)->list[bytes] (filter empty), reassemble(frames)->bytes (b"".join(frames)), check_crc(block)->bool (sum(block)%2==0), extract_telemetry(block)->bytes (block[4:]), sequence_ok(seq)->bool (consecutive ascending)
link.py: compute_link_budget(ptx,grx,freq,dist)->float (ptx+grx-20*log10(dist)), snr_to_ber(snr)->float (10**(-snr/10)), bandwidth_efficiency(m,c)->float (m*c), doppler_shift(f,vel)->float (f*vel/299792458.0), propagation_delay(dist)->float (dist/299792458.0)
eph.py: mean_anomaly(raan,inc,t)->float (raan+inc*t), orbital_period(sma)->float (2*pi*sqrt(sma**3/398600.4418)), eccentric_anomaly(e,m)->float (m+e*sin(m)), true_anomaly(e,E)->float (2*atan2(sqrt(1+e)*sin(E/2),sqrt(1-e)*cos(E/2))), ground_track_speed(alt)->float (2*pi*(6371.0+alt)/86400.0)
decoder.py: parse_packet(blob)->dict ({"len":len(blob),"id":blob[0]}), decode_telemetry(data)->list[int] (list(data)), extract_health(telem)->str (str(telem.get("health","OK"))), checksum_valid(pkt)->bool (sum(pkt)%256==0), deserialize_field(buf,off)->int (buf[off])
Create sats/__init__.py re-exporting all 20, and sats/verify.py asserting all 20 against concrete values; run verify.py until it passes. Report a one-line summary.'

STfull='Working directory: %DIR%. Manage this with a statem runbook (statem skill loaded) at %DIR%/sats/statem.yaml, nodes: plan,framer,link,eph,decoder,verify,done. On verify add a before_transfer gate running python3 sats/verify.py that asserts all 20 functions; must pass before done. Start: statem start statem.yaml --run-id c --json. Implement all four modules per the contract, statem save then statem goto <next> --run-id c --yes --json after each. Then build the package:
'"$FULL"

declare -A MOD
MOD[framer]='framer.py: deframe(packets: list[bytes]) -> list[bytes] (filter empty byte objects); reassemble(frames: list[bytes]) -> bytes (b"".join(frames)); check_crc(block: bytes) -> bool (sum(block) % 2 == 0); extract_telemetry(block: bytes) -> bytes (block[4:]); sequence_ok(seq: list[int]) -> bool (strictly consecutive ascending)'
MOD[link]='link.py: compute_link_budget(ptx, grx, freq, dist) -> float (ptx + grx - 20*log10(dist)); snr_to_ber(snr) -> float (10**(-snr/10)); bandwidth_efficiency(mod_order, coderate) -> float (mod_order*coderate); doppler_shift(freq, vel) -> float (freq*vel/299792458.0); propagation_delay(dist) -> float (dist/299792458.0)'
MOD[eph]='eph.py: mean_anomaly(raan, inc, t) -> float (raan + inc*t); orbital_period(sma) -> float (2*pi*sqrt(sma**3/398600.4418)); eccentric_anomaly(e, m) -> float (m + e*sin(m)); true_anomaly(e, E) -> float (2*atan2(sqrt(1+e)*sin(E/2), sqrt(1-e)*cos(E/2))); ground_track_speed(alt) -> float (2*pi*(6371.0+alt)/86400.0)'
MOD[decoder]='decoder.py: parse_packet(blob) -> dict ({"len": len(blob), "id": blob[0]}); decode_telemetry(data) -> list[int] (list(data)); extract_health(telem) -> str (str(telem.get("health","OK"))); checksum_valid(pkt) -> bool (sum(pkt) % 256 == 0); deserialize_field(buf, offset) -> int (buf[offset])'

echo "########## MODE: sequential ##########"
DSEQ=/tmp/comp_seq
T0=$(date +%s)
cd "$DSEQ"
omp -p "${FULL//%DIR%/$DSEQ}" --model deepseek/deepseek-v4-flash > /tmp/comp_seq.log 2>&1
T1=$(date +%s); echo "seq wall=$(($T1-$T0))s"; tail -1 /tmp/comp_seq.log

echo "########## MODE: statem-sequential ##########"
DST=/tmp/comp_statem
T0=$(date +%s)
cd "$DST"
omp -p "${STfull//%DIR%/$DST}" --model deepseek/deepseek-v4-flash > /tmp/comp_statem.log 2>&1
T1=$(date +%s); echo "statem-seq wall=$(($T1-$T0))s"; tail -1 /tmp/comp_statem.log

echo "########## MODE: parallel (4 sub-agents + coordinator) ##########"
DPAR=/tmp/comp_parallel
cd "$DPAR"
T0=$(date +%s)
for m in framer link eph decoder; do
  omp -p "Working directory: $DPAR. Implement the Python module at $DPAR/${m}.py with EXACTLY these functions and behavior: ${MOD[$m]}. Do NOT create other files. Verify it imports, then report one line." --model deepseek/deepseek-v4-flash > /tmp/comp_parallel_$m.log 2>&1 &
done
wait
T1=$(date +%s); echo "parallel leaves wall=$(($T1-$T0))s"
omp -p "Working directory: $DPAR. The files framer.py, link.py, eph.py, decoder.py exist here. Write __init__.py re-exporting all 20 functions, and verify.py that imports all 20 and asserts them against concrete expected values. Run python3 verify.py until it passes. Report one line." --model deepseek/deepseek-v4-flash > /tmp/comp_parallel_coord.log 2>&1
T2=$(date +%s); echo "parallel total wall=$(($T2-T0))s (leaves $(($T1-T0))s + coord $(($T2-T1))s)"; tail -1 /tmp/comp_parallel_coord.log
echo "=== ALL MODES DONE ==="
