---
name: statem
description: Manage long omp work with statem state-machine runbooks. Use when tasks need durable state, explicit transitions, redo loops, save/resume behavior, or cross-agent review.
---

# Statem

Use `statem` as a state-aware runbook for long omp agent runs. It should guide the work and preserve progress without turning the session into a rigid workflow harness.

## Operating Loop

1. Inspect or create a spec such as `statem.yaml`.
2. Validate it: `statem validate statem.yaml --json`.
3. Start or resume a run: `statem start statem.yaml --run-id <id> --json`.
4. Before acting, check state: `statem cur --run-id <id> --json`.
5. Move only through allowed edges: `statem goto <node> --run-id <id> --json`.
6. Save progress before pausing: `statem save --run-id <id> --json`.
7. For handoff context, read recent history: `statem history --run-id <id> --tail 10 --json`.

The `statem` command is provided by this plugin's `bin/statem` launcher. If it is not on PATH, call it directly as `<plugin_root>/bin/statem` (or `python3 -m statem` from the plugin root, which bundles the Python package).

For dynamic servers, company machines, or disposable git checkouts, prefer a
machine-local state directory. Set `STATEM_STATE_DIR` once, for example
`$HOME/.local/state/statem/<project>`, so runtime state survives checkout
replacement. After moving to a new checkout, run `statem start <spec> --run-id
<id>` once to rebind the run to the current spec path.

Commit YAML runbooks with the repo. Do not commit runtime state; treat `.statem/`
or `STATEM_STATE_DIR` as local, copy-on-use execution data.

## Loop Compaction

For cyclic runbooks, prefer an explicit session-hygiene node after a full loop.
When continuing another cycle and the context is noisy, generate a safe compaction
instruction:

```bash
statem compact-prompt --run-id <id>
```

Run the generated `/compact` instruction through the omp UI, then recover with
`statem cur` and `statem history --tail 10`. Do not use hidden self-messaging to
trigger compaction.

Agents may inspect the full graph with `statem state`; `cur`, `next`, and `goto`
are for disciplined execution and attention anchoring, not for hiding the runbook.

## Auto Loop Hook

omp supports hooks (see the omp hooks docs). Users may opt into auto-loop
behavior with `integrations/hooks/statem_stop_hook.py`, which fires when the
agent is about to hand control back to the user. If a statem run is active, the
current node is not a terminal/handoff node, and there are outgoing transitions,
it returns a continuation prompt telling the agent to inspect `statem cur` and
keep working from the current node.

Register it as a post-request hook in the omp plugin or project hook config.
Use an absolute script path if the hook is registered outside this plugin repo.

Treat this as host-level glue. It must not advance state, run `/compact`, or hide
the graph. The agent should still transition only with `statem goto`.

## Spec Guidance

- Keep the static spec separate from `.statem/` runtime state.
- Use natural-language checks for low-friction runbooks.
- Use `in_hook` for setup after entering a node.
- Use `before_transfer` for redo/check loops while still in the current node.
  It is a spec field, not a CLI command; `statem goto` runs it automatically.
- Use `out_hook` to persist current-node progress before leaving.
- Use edge `hook` as prepare-transfer work after `out_hook` and before entering
  the target. If a blocking edge hook fails, the pointer stays at the source so
  the agent can retry.
- Use `type: command` for deterministic shell checks and hooks.
- Use `type: predicate` for file existence, non-empty files, text matches, and
  JSON-path checks.
- Use `type: llm_review` when another model, agent, or script should review
  before a transition.
- Treat blocked transitions as useful feedback: stay in the node, fix the issue,
  then retry.

Do not manually edit `.statem/runs/<run-id>/state.json` unless the user explicitly
asks for runtime surgery.

## Reviewing a Spec

Run `statem validate <spec> --json`. Check that each node has a clear prompt,
each edge has an understandable condition, and risky transitions have
`before_transfer` checks. Flag hooks that mutate broad state, lack timeouts, or
can block unexpectedly.
