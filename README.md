# statem-omp

Stateful runbooks for long-running agents — packaged as an [omp](https://omp.sh) marketplace and plugin.

[statem](https://github.com/henryqin1997/statem) turns an agent workflow into an inspectable
graph of states, transitions, and executable checks. This repo packages the statem CLI as an omp
plugin: install it and your agent can create, validate, start, resume, inspect, and transition
through state-aware runbooks without losing sight of long-running work.

## Repo layout

- `.omp-plugin/marketplace.json` — the omp marketplace catalog.
- `plugins/statem/` — the omp plugin:
  - `plugin.json` — omp plugin manifest.
  - `skills/statem/SKILL.md` — the skill omp loads so the agent knows how to drive statem.
  - `bin/statem` — a launcher that resolves the statem CLI (installed, `STATEM_REPO`, or bundled).
  - `statem/` — the statem Python package, vendored, so the plugin works with no pip install.
  - `examples/coding-agent.yaml` — a starter runbook.
  - `integrations/hooks/statem_stop_hook.py` — optional auto-loop Stop hook.

## Benchmarks

We ran controlled baseline-vs-statem comparisons with DeepSeek-V4-Flash through omp.
Bottom line: statem adds overhead and no correctness win on short single-shot tasks, and it is
**not magic** (a weak verify gate gives weak protection) — but it **wins where it's designed to**:
durable state across a context wipe, where baseline loses the contract and statem resumes from its
runbook and passes.

| Scenario | baseline | statem |
|----------|----------|--------|
| short 4-step build | ✅ PASS | ✅ PASS |
| large 20-fn 9-phase build | ✅ PASS | ✅ PASS |
| git-webserver deploy (TB 2.1 task) | ✅ PASS | ✅ PASS |
| two-session build, subtle drift | ❌ FAIL | ❌ FAIL |
| **two-session build, context wiped** | ❌ FAIL | ✅ **PASS** |

Full methodology, task details, timing, and the exact failure modes are in
[`benchmarks.md`](benchmarks.md), with reproducible harness scripts under `benchmarks/`.

## Requirements

- omp (oh-my-pi) — `curl -fsSL https://omp.sh/install | sh`
- Python 3.11+ (the statem CLI is pure Python, zero runtime dependencies)

## Install

Install from the marketplace (recommended):

```sh
omp plugin marketplace add slab-nano/statem-omp
omp plugin install statem@statem-omp
```

Or from a local checkout while developing:

```sh
omp plugin marketplace add ./statem-omp
omp plugin install statem@statem-omp
```

Then run `/reload-plugins` (or restart omp) to pick up the skill. Verify with:

```sh
omp plugin list
omp -p /extensions   # the statem skill should appear
```

## Usage

The skill is loaded on demand. In a task, ask omp to "create a statem runbook for this
task" or drive statem directly:
```sh
statem validate statem.yaml --json
statem start statem.yaml --run-id myrun --json
statem cur --run-id myrun --json
statem goto <next> --run-id myrun --json
statem save --run-id myrun --json
statem history --run-id myrun --tail 10 --json
```

If `statem` is not on PATH, use `<plugin_root>/bin/statem` (or `python3 -m statem` from the
plugin root).

See [`examples/coding-agent.yaml`](examples/coding-agent.yaml) for a starter spec, and the
upstream [statem docs](https://henryqin1997.github.io/statem/) for full runbook semantics.

## Auto Loop Hook (optional)

To auto-continue work until a runbook reaches a handoff node, register
`integrations/hooks/statem_stop_hook.py` as an omp post-request hook. See the file header
and the upstream statem hook docs.

## License

Apache-2.0. Upstream statem is Apache-2.0 (© Ziheng Qin and contributors).
