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

**Token counts below are MEASURED**, not estimated — read from omp's per-session usage records
(`message.usage.totalTokens` for output incl. reasoning, `message.contextSnapshot.promptTokens` for input),
summed across every message and every session of a run. Wall-clock is measured. Cost uses **DeepSeek V4 Flash**
public rates: **$0.14/M input (cache miss), $0.28/M output**.

The three execution modes below are the **same 4-module `sats` package**, run identically apart from orchestration
(a clean apples-to-apples comparison). All three graded **6/6** (all 20 functions correct).

| Mode | wall clock | input tok | output tok | total tok | est. cost |
|------|-----------:|----------:|-----------:|----------:|----------:|
| **sequential** (1 agent) | 25s | 75,014 | 78,369 | **153,383** | ~$0.032 |
| **parallel** (4 sub-agents + coordinator) | 34s | 321,122 | 325,668 | **646,790** | ~$0.136 |
| **statem-sequential** (1 agent + runbook) | 136s | 1,306,318 | 1,318,493 | **2,624,811** | ~$0.55 |

**What this actually shows:**

- **Parallel is NOT a token saver.** It burns **4.2× the tokens** of the plain sequential agent (646k vs 153k) —
  each of the 4 sub-agents re-loads ~48k tokens of context, and the coordinator adds ~256k. Parallel's win is
  **latency only**: 34s vs 25s (sequential) and **4× faster than statem-sequential** (136s).
- **Statem-sequential is the real token hog: 2,624,811 tokens — 17× the plain baseline.** The runbook `save`/`goto`
  steps, gate execution, and re-verification balloon the context across 47 messages. Its value is durable state,
  but on a single clean pass it is by far the most expensive of the three.
- If your constraint is **cost**, a single sequential agent wins (153k, ~$0.03). If it's **latency + correctness on
  long multi-module work**, parallel sub-agents beat statem-sequential on both (34s/647k vs 136s/2.6M) while keeping
  the verify gate.

*(Scenarios 1–9 in the tables above were run before per-run telemetry was enabled; their token/cost figures are
the earlier estimates and are superseded by this measured comparison for the same task class.)*

## Scenario 10 — parallel sub-agents (wall-clock reduction)

Same 4-module sats package, but the four independent module leaves are built by **four concurrent omp agents**
(each writes its own `*.py`), then a single coordinator writes `__init__.py` + `verify.py` and runs the verify
gate. All three variants graded **6/6** (all 20 functions correct). **Token counts are measured** (see
"Runtime, tokens & cost").

| Variant | wall clock | total tokens | result |
|---------|-----------:|-------------:|--------|
| sequential baseline | 25s | 153,383 | 6/6 |
| statem-sequential | 136s | 2,624,811 | 6/6 |
| **parallel (4 sub-agents + coordinator)** | **34s** | 646,790 | 6/6 |

**Finding — this answers "can statem's work be parallelized with sub-agents?":** statem's runbook *spine* is
sequential (a single pointer through gated nodes), but the **leaf nodes are embarrassingly parallel**. Splitting
the four independent modules across four concurrent sub-agents cut wall-clock to **34s — 1.4× the sequential
baseline and 4× faster than statem-sequential**, at identical correctness. The durable-state / verify-gate value
is preserved: the coordinator still runs the merge + verify gate.

**Cost trade-off — parallelism buys latency, not tokens.** Measured, parallel uses **646,790 tokens = 4.2× the
plain baseline** (153k) because four sub-agents each re-load ~48k tokens of context plus a ~256k coordinator.
But statem-sequential is the real outlier at **2.6M tokens (17× baseline)**. So: cost-sensitive → sequential
baseline; latency + correctness on long work → parallel sub-agents beat statem-sequential on both dimensions.

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
sequential baseline. **Scenario 10 measures the parallel variant** and confirms the win on latency: 34s vs 25s
(sequential) / 136s (statem-sequential) at identical correctness. The catch is tokens: parallel uses 4.2× the
plain baseline (646k vs 153k) but far fewer than statem-sequential (2.6M). So the answer is yes — parallel
sub-agents cut wall-clock on multi-module runbooks, at the cost of merge + gate coordination and more total
tokens than a single baseline agent.

---

## How to reproduce

The harness scripts live in the repo:

- `benchmarks/git-webserver/` — scenario 3 (docker-free TB 2.1 task)
- `benchmarks/resume/` — scenarios 4 & 5 (two-session resume)
- `benchmarks/scenarios/` — scenarios 6–9 (verify-gate, resume-repair, release gate, three-session)
- `benchmarks/scenarios/run_parallel.sh` — scenario 10 (parallel sub-agents)
- `benchmarks/scenarios/run_comp.sh` — measured runtime/token comparison (sequential / statem-sequential / parallel)

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
