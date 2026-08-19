# Benchmarks

Controlled baseline-vs-statem comparisons, run on a modest box (2 vCPU / 3.8 GB RAM, no GPU)
with **DeepSeek-V4-Flash** (`deepseek/deepseek-v4-flash`) via [omp](https://omp.sh) and this plugin's
statem skill. Each row is the same task given to omp with the statem plugin **enabled** vs a plain
baseline omp run (no skill). All runs are real executions; none are fabricated.

## Summary

| # | Scenario | What it tests | baseline | statem |
|---|----------|---------------|----------|--------|
| 1 | 4-step package build | basic correctness on a short task | ✅ PASS (46s) | ✅ PASS (92s) |
| 2 | 20-function, 9-phase build | correctness on a large single-shot task | ✅ PASS (168s) | ✅ PASS (191s) |
| 3 | Git-webserver deploy (Terminal-Bench 2.1 task, docker-free) | real multi-service terminal task | ✅ PASS (21s) | ✅ PASS (107s) |
| 4 | Two-session build, subtle contract drift | does a verify gate catch drift? | ❌ FAIL (8/9) | ❌ FAIL (8/9) |
| 5 | Two-session build, non-inferable API, context wiped | does durable state survive a context wipe? | ❌ FAIL (5/6) | ✅ **PASS (6/6)** |
| 6 | Verify-gate repair loop (string-input drift) | does a strict gate catch a silent bug? | ❌ FAIL (1/2) | ✅ **PASS (2/2)** |
| 7 | Resume-with-repair (even-length median bug) | does durable failure state survive a wipe? | ✅ PASS (2/2) | ✅ PASS (2/2) |
| 8 | Invalid-transition blocking (release gate) | does a gate block skipping tests? | ✅ PASS (4/4) | ✅ PASS (4/4) |
| 9 | Three-session resume (two context wipes) | durable state across a longer interruption chain | ✅ PASS (6/6) | ✅ PASS (6/6) |
| 10 | Parallel sub-agents (4 modules) | can independent leaves cut wall-clock? | — | ✅ PASS (6/6) in 62s |

Scores are objective: an external hidden grader (independent of the agent's own self-checks).

---

## Scenario 1 — short 4-step build

Build `app/adder.py`, `tests/test_adder.py`, run pytest green, write README.

- baseline: 4/4 deliverables, pytest 2 passed, 46s.
- statem: 4/4 deliverables, pytest 2 passed, 92s. Ran a statem runbook `plan→app→tests→verify→docs→done`,
  including a mid-run `resume` from durable state.

**Finding:** on short single-shot tasks statem matches correctness but adds ~2× wall-clock
overhead from runbook management. It is not a speed win here.

## Scenario 2 — large 20-function, 9-phase build

Build a 4-module accounting/forecast/scheduling package with an exact 20-function contract, a strict
`verify.py`, and pytest. Scored by an objective 15-check grader.

- baseline: 15/15, 168s.
- statem: 15/15, 191s. Traversed all 9 runbook nodes with a `before_transfer` pytest gate.

**Finding:** DeepSeek-V4-Flash is strong enough single-shot that baseline did not fail even on this
large task. Statem matched correctness at ~14% overhead. No rescue needed.

## Scenario 3 — git-webserver deploy (real Terminal-Bench 2.1 task)

A faithful, docker-free reproduction of the TB 2.1 `configure-git-webserver` family: configure a bare
git repo with a `post-receive` hook that deploys to a web root, run an HTTP server on :8080, and be
graded by a fresh `clone → commit → push → curl :8080/hello.html == "hello world"`.

- baseline: PASS, 21s (wrote a correct hook, left a detached server running).
- statem: PASS, 107s (runbook `env_ready→deploy_hook→web_server→verify→done`, curl gate enforced).

**Finding:** baseline passed this genuinely multi-service task too. The runnable TB 2.1 subset is in
the same difficulty band as our synthetic tasks, so it does not produce a baseline failure on this
hardware. (The heavy TB 2.1 / TB 3.0 tasks where baseline genuinely fails need Docker, more RAM,
and GPU — not runnable on this box.)

## Scenario 4 — two-session build with subtle contract drift

Two omp sessions (context wiped between). Session 1 builds `fin/ledger.py` + `fin/ratios.py` and
writes a spec; session 2 implements the rest. The contract requires string date inputs; both agents
implemented `date`-object inputs. An external grader tests string inputs → both fail.

- baseline: 8/9 FAIL (sched functions accept only `date`, not `str`; its own verify.py used `date` and passed).
- statem: 8/9 FAIL (same bug; its verify gate enforced the same loose check).

**Finding — important and honest:** statem is **not magic**. It only enforces whatever checks the
agent puts in the runbook/verify. A weak gate gives weak protection. The durable-state value does
not fix a contract the agent never encoded.

## Scenario 5 — two-session build, non-inferable API, context wiped ✅ statem win

The scenario that isolates statem's real value: a domain-specific API whose exact function names are
non-inferable. Session 1 (both) is given the full 20-function contract across 4 modules, implements
2 modules, and stops. **Baseline persists nothing; statem persists the full contract inside its
runbook.** Session 2 (context wiped, short prompt) must finish.

- **baseline: FAIL (5/6)** — with the contract gone, session 2 guessed the remaining API and drifted
  (`mean_motion`/`radial_distance`/`orbital_velocity` instead of the required
  `mean_anomaly`/`ground_track_speed`, etc.). The external grader's import failed.
- **statem: PASS (6/6)** — session 2 ran `statem cur` / `statem history`, read the exact contract
  embedded in the runbook's `eph`/`decoder` node prompts, implemented all 20 correctly, and reached
  `done`. Durable state at `.statem/runs/sat/state.json`; history
  `start→framer→link→eph→decoder→verify→docs→done`.

**Finding — the regime statem actually wins:** **durable state across context loss.** When an agent's
plan/contract lives only in context and that context is wiped, a stateless agent loses it; statem's
runbook survives and lets the next session resume precisely. This is the failure mode the statem paper
targets (long runs, context refresh), and it is where the plugin pays for itself.

---

## Scenario 6 — verify-gate repair loop (string-input drift) ✅ statem win

Single session. Implement `cal.weekdays_between(a, b)` counting weekdays between two dates inclusive. The
contract requires **ISO string** inputs. Baseline naturally implemented `date`-object inputs and its own
self-check used `date` objects, so it passed its own check but **failed** the hidden grader (`TypeError: 'str'
and 'str'`). Statem's runbook had a **strict `before_transfer` gate that tested string inputs**, which failed,
blocked the agent from leaving `verify`, and forced it to fix `cal.py` to accept strings — then the gate passed.

- baseline: FAIL (1/2) — silent string-input drift, loose self-check missed it.
- statem: PASS (2/2) — enforced gate caught and repaired the bug.

**Finding:** this is the honest win for **enforced verification**. Contrast with scenario 4: statem is only as
good as its gate. Here the runbook gate tested the *real* contract (string inputs), so it caught what a loose
self-check missed.

## Scenario 7 — resume-with-repair (even-length median bug)

Two sessions, context wiped. The subtle bug: `median()` wrong for even-length lists (e.g. `median([1,3,2,4])`).
Both trials happened to implement even-length median correctly, so **both passed** the hidden grader — no
difference. Statem did record and carry its failure/verify state correctly across the wipe.

- baseline: PASS (2/2). statem: PASS (2/2). **Null result** — baseline just got the subtle rule right this time.

## Scenario 8 — invalid-transition blocking (release gate)

Single session. Build `svc/app.parse_version` with a release step that requires green tests. Statem's runbook
forced `implement → test → release` (a `before_transfer` pytest gate blocks `release` unless green). Both trials
implemented `parse_version` correctly and produced a valid release, so **both passed** — no difference.

- baseline: PASS (4/4). statem: PASS (4/4). **Null result** — baseline didn't rush/skip this time.

## Scenario 9 — three-session resume (two context wipes)

The scenario-5 design stretched across three sessions and two wipes (framer+link → eph+decoder → verify+docs).
Baseline inferred the non-inferable API from the domain across both wipes and passed; statem resumed from its
runbook each time and passed. Functional grades are equal (6/6).

- baseline: PASS (6/6). statem: PASS (6/6).
- Note: the first statem run of this scenario was interrupted mid-session-3 by a `402 Insufficient Balance`
  (DeepSeek API balance exhausted); after a top-up it was re-run to completion cleanly (all three sessions,
  ending at `done` with the verify gate enforced). The numbers below are the completed run.

---

## Runtime, tokens & cost

Wall-clock times below are measured. **Token counts are estimates** — omp's `-p --no-session` runs did not
persist per-run usage telemetry, and the API balance ran out before I could re-run with logging enabled.
Estimated tokens use ~3,000 tokens/sec of **agent-seconds** (each agent's run duration summed; for the parallel
run that is 4 sub-agents + 1 coordinator, NOT the 62s wall-clock, since concurrent agents burn tokens
simultaneously). Cost uses **DeepSeek V4 Flash** public rates: **$0.14/M input (cache miss), $0.28/M output** →
blended ~**$0.168/M** (80/20 input/output split).

| Scenario | Trial | wall clock | est. tokens | est. cost |
|----------|-------|-----------:|------------:|----------:|
| 5 sats resume | baseline | 129s | ~387k | ~$0.065 |
| 5 sats resume | statem | 238s | ~714k | ~$0.12 |
| 6 verify-gate | baseline | 21s | ~63k | ~$0.011 |
| 6 verify-gate | statem | 85s | ~255k | ~$0.043 |
| 7 resume-repair | baseline | 30s | ~90k | ~$0.015 |
| 7 resume-repair | statem | 243s | ~729k | ~$0.12 |
| 8 release gate | baseline | 70s | ~210k | ~$0.035 |
| 8 release gate | statem | 70s | ~210k | ~$0.035 |
| 9 three-session | baseline | 107s | ~321k | ~$0.054 |
| 9 three-session | statem | 323s | ~969k | ~$0.16 |
| 10 parallel sub-agents | statem-parallel | **62s** | ~420k | ~$0.071 |

**Takeaway on cost/overhead:** DeepSeek V4 Flash is extremely cheap — every run here is on the order of
$0.01–$0.16. Statem's sequential runs consistently spend **more** wall-clock and tokens (roughly 2–8×) because
the runbook, `save`/`goto` transitions, and verify gates add real work and reasoning. In the cases where statem
wins (5, 6) it buys correctness; in the null cases (7, 8, 9) it buys the same answer for more tokens. The
**parallel sub-agent** variant is the exception — see scenario 10.

## Scenario 10 — parallel sub-agents (wall-clock reduction)

Same 4-module sats package, but the four independent module leaves are built by **four concurrent omp agents**
(each writes its own `*.py`), then a single coordinator writes `__init__.py` + `verify.py` and runs the verify
gate. All 20 functions graded correct (6/6), identical to the sequential runs.

| Variant | wall clock | result |
|---------|-----------:|--------|
| sequential baseline | 107s | 6/6 |
| statem-sequential | 323s | 6/6 |
| **statem-parallel (4 sub-agents + coordinator)** | **62s** | 6/6 |

**Finding — this answers "can statem's work be parallelized with sub-agents?":** statem's runbook *spine* is
sequential (a single pointer through gated nodes), but the **leaf nodes are embarrassingly parallel**. Splitting
the four independent modules across four concurrent sub-agents cut wall-clock to **62s — 1.7× faster than the
sequential baseline and 5.2× faster than statem-sequential**, with identical correctness. The durable-state /
verify-gate value is preserved: the coordinator still runs the merge + verify gate.

**Cost trade-off — parallelism buys latency, not tokens.** Measured by **agent-seconds** (each agent's runtime
summed), the parallel run burns ~140 agent-sec ≈ **~420k tokens** — *more* than the single baseline agent
(~321k, from 4 agents loading context + a coordinator), but *far fewer* than statem-sequential (~969k, which
re-does runbook setup + verification across 3 sessions). So parallel sub-agents are the right tool when
**wall-clock latency** matters; if **total tokens / cost** is the constraint, a single sequential baseline agent
is cheapest, and statem-sequential is the most expensive of the three.

## Can statem's work be parallelized with sub-agents?

Statem itself is **sequential by design** — a run is a single pointer advancing through nodes, and each `goto`
depends on the previous node's state and gates. So the runbook *execution* cannot be trivially split. But the
**leaves of a runbook can**:

- Independent sibling nodes (e.g. implementing four independent modules) are natural sub-agent candidates.
  Launch them in parallel, each writing to its own working file, then have a coordinator run the `verify` node
  against the merged result. This can cut wall-clock substantially on a multi-module runbook (e.g. scenario 9's
  four modules could be 4 parallel sub-agents instead of 4 sequential sessions).
- The durable-state benefit is orthogonal: sub-agents do the parallel leaf work; statem still owns the
  ordered, gated spine (which phases are done, which gate must pass before merge/handoff).

In this harness we ran everything as one omp agent per session (no sub-agents), so the numbers above are the
sequential baseline. **Scenario 10 measures the parallel variant** and confirms the expected win: 62s vs 107s
(sequential) / 323s (statem-sequential) at identical correctness. So the answer is yes — parallel sub-agents
cut wall-clock on multi-module runbooks, at the cost of merge + gate coordination and slightly more total tokens
than a single baseline agent.

---

## How to reproduce

The harness scripts live in the repo:

- `benchmarks/git-webserver/` — scenario 3 (docker-free TB 2.1 task)
- `benchmarks/resume/` — scenarios 4 & 5 (two-session resume)
- `benchmarks/scenarios/` — scenarios 6–9 (verify-gate, resume-repair, release gate, three-session)
- `benchmarks/scenarios/run_parallel.sh` — scenario 10 (parallel sub-agents)

```bash
# scenario 3, baseline then statem
bash benchmarks/git-webserver/run_trial.sh baseline
bash benchmarks/git-webserver/run_trial.sh statem

# scenario 5 (and 4), baseline then statem
bash benchmarks/resume/run_sats.sh baseline
bash benchmarks/resume/run_sats.sh statem
bash benchmarks/resume/score_sats.sh /tmp/sats_baseline
bash benchmarks/resume/score_sats.sh /tmp/sats_statem

# scenarios 6–9 (A–D), baseline then statem
for s in A B C D; do
  bash benchmarks/scenarios/run_$s.sh baseline
  bash benchmarks/scenarios/run_$s.sh statem
  bash benchmarks/scenarios/score_$s.sh /tmp/$(echo $s | tr A-Z a-z)_baseline
  bash benchmarks/scenarios/score_$s.sh /tmp/$(echo $s | tr A-Z a-z)_statem
done
```

Requires: `omp` (oh-my-pi), the statem plugin, `statem` on PATH, git + python3 + pytest.
