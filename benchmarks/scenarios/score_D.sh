#!/usr/bin/env bash
# Hidden grader for Scenario D (same as sats all-20). Usage: score_D.sh <dir>
set -uo pipefail
D="$1"; S="$D/sats"; pass=0; fail=0
ck(){ if [ -e "$1" ]; then echo "PASS  $2"; pass=$((pass+1)); else echo "FAIL  $2"; fail=$((fail+1)); fi; }
for f in framer link eph decoder __init__; do ck "$S/$f.py" "$f.py"; done
PY="python3"; [ -x "$D/.venv/bin/python" ] && PY="$D/.venv/bin/python"
if $PY - "$S" >/tmp/dd.log 2>&1 <<'PYEOF'
import sys, math
S=sys.argv[1]; sys.path.insert(0,S)
from framer import deframe,reassemble,check_crc,extract_telemetry,sequence_ok
from link import compute_link_budget,snr_to_ber,bandwidth_efficiency,doppler_shift,propagation_delay
from eph import mean_anomaly,orbital_period,eccentric_anomaly,true_anomaly,ground_track_speed
from decoder import parse_packet,decode_telemetry,extract_health,checksum_valid,deserialize_field
ok=True
ok &= deframe([b"",b"ab",b"c"])==[b"ab",b"c"] and reassemble([b"a",b"b"])==b"ab"
ok &= check_crc(b"\x01\x02\x03")==True and check_crc(b"\x01\x02")==False
ok &= extract_telemetry(b"\x01\x02\x03\x04\xff\x00")==b"\xff\x00" and sequence_ok([1,2,3]) and not sequence_ok([1,3,4])
ok &= abs(compute_link_budget(50,40,900e6,1000)-(90-20*math.log10(1000)))<1e-6
ok &= abs(snr_to_ber(10)-10**(-1.0))<1e-9 and bandwidth_efficiency(4,0.5)==2.0
ok &= abs(doppler_shift(2.4e9,3000)-(2.4e9*3000/299792458.0))<1e-3 and abs(propagation_delay(299792458)-1.0)<1e-6
ok &= abs(mean_anomaly(1,2,3)-7)<1e-9 and abs(orbital_period(7000)-(2*math.pi*math.sqrt(7000**3/398600.4418)))<1e-3
ok &= abs(eccentric_anomaly(0.1,1.0)-(1.0+0.1*math.sin(1.0)))<1e-9
ok &= abs(ground_track_speed(400)-(2*math.pi*(6371.0+400)/86400.0))<1e-6
ok &= parse_packet(b"\x05ab")=={"len":3,"id":5} and decode_telemetry(b"\x01\x02")==[1,2]
ok &= extract_health({"health":"NOMINAL"})=="NOMINAL" and checksum_valid(b"\x00\x00") and not checksum_valid(b"\x01")
ok &= deserialize_field(b"\x0a\x0b",1)==11
print("PASS" if ok else "FAIL_vals")
PYEOF
then
  if grep -q PASS /tmp/dd.log; then echo "PASS  all 20 correct"; pass=$((pass+1)); else echo "FAIL  behavior: $(grep FAIL /tmp/dd.log)"; fail=$((fail+1)); fi
else echo "FAIL  import: $(tail -1 /tmp/dd.log)"; fail=$((fail+1)); fi
echo "== SCORE: $pass pass / $fail fail =="
