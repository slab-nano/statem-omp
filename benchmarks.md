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

## How to reproduce

The harness scripts used for scenarios 3–5 live in the repo:

- `benchmarks/git-webserver/` — scenario 3 (docker-free TB 2.1 task)
- `benchmarks/resume/` — scenarios 4 & 5 (two-session resume)

```bash
# scenario 3, baseline then statem
bash benchmarks/git-webserver/run_trial.sh baseline
bash benchmarks/git-webserver/run_trial.sh statem

# scenario 5, baseline then statem
bash benchmarks/resume/run_sats.sh baseline
bash benchmarks/resume/run_sats.sh statem
bash benchmarks/resume/score_sats.sh /tmp/sats_baseline
bash benchmarks/resume/score_sats.sh /tmp/sats_statem
```

Requires: `omp` (oh-my-pi), the statem plugin, `statem` on PATH, git + python3.
