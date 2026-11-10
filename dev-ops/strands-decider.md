# Strands Decider — investigation for our development process

Date: 2026-11-10  
Source: https://github.com/strands-labs/strands-decider (Apache-2.0)

## 1. What it is

Strands Decider is a small "system-one" decision model (~2B–26B parameters). Unlike an LLM it
does not generate text; in one forward pass it answers one of three question types and returns
a probability distribution plus a **calibrated confidence**:

- `noul` — yes/no, returns P(yes).
- `choice` — pick one of 2–255 named options, returns the pick, every option's probability,
  and a confidence.
- `score` — an ordered rubric of 2–10 levels, returns the expected level and a confidence.

It serves over HTTP (`strands-decider serve ... --port 8000`, endpoint `/v1/systemone`) and runs
on CPU or GPU. On short classification tasks, answers at confidence ≥ 0.9 are right ~95% of the
time; below that, confirm or escalate. Latency is ~100–250 ms per question, and many questions
about one state are cheap because the state is read once.

Natural fit (per upstream): model routing, tool selection, argument checking, **triage**, guardrails
and policy classification, **evaluations / answer-adequacy checks**, and hybrid agents where the
LLM does the hard decisions and the decider does the rote ones.

## 2. Where our development process has rote decisions

Our process is an agentic software factory (`.opencode/agents/`, `dev-ops/factory/`). Decisions
that are currently made by an LLM (planner/builder/fixer/reviewer) and are well suited to a
decider:

| # | Decision | Current owner | Type | Options / scale |
|---|----------|---------------|------|-----------------|
| A | Area labels on an infant issue | planner | choice | `backend`, `frontend`, `dev-ops` (multi) |
| B | Size label | planner | choice | `size/S`, `size/M`, `size/L` |
| C | Complexity tier → model routing | planner / `models.yaml` | choice | `trivial`, `light`, `standard`, `heavy` |
| D | `ready-for-build` vs `needs-info` | planner | noul | "is this sufficiently specified?" |
| E | Issue has measurable acceptance criteria (issue #91) | (hook) | noul | yes/no |
| F | PR weakens a guardrail (CI config, thresholds, skips) | reviewer | noul | yes/no |
| G | PR is in scope / has unrelated changes | reviewer | noul | yes/no |
| H | Builder output satisfies acceptance criteria | reviewer/builder | score | 0–5 rubric |
| I | Triage a QA failure/deployment issue to owner | (human) | choice | `backend`, `frontend`, `dev-ops`, `infra` |

These are classification/scoring decisions with a fixed option set — exactly the decider's sweet
spot. They are also frequent and cheap to get wrong, so a fast, calibrated first pass with
escalation is valuable.

## 3. Proposed use (hybrid, confidence-gated)

Do not replace the LLM agents. Use the decider as a **fast first pass** and let the LLM (or a
human) handle low-confidence cases:

- **High confidence (≥ 0.9):** act automatically (apply label, route model, gate PR).
- **Mid (0.5–0.9):** apply tentatively / flag for review.
- **Low (< 0.5):** defer to the LLM agent or human.

This mirrors upstream's "act on confident answers, send the rest to an LLM or a person" and keeps
the factory's auditability (labels/comments remain the source of truth).

Concrete pilots, in priority order:

1. **Pilot 1 — Issue triage classifier (decision A–D).** Run a decider over each infant issue's
   title+body and propose area/size/complexity/needs-info. The planner still posts the plan and
   applies labels, but is seeded with the decider's proposal + confidence. Measures: label
   agreement with historical planner labels, and reassignment rate.
2. **Pilot 2 — Acceptance-criteria gate (E).** A noul check feeding issue #91's hook: block
   planning when confidence is high that criteria are missing; otherwise let the planner decide.
3. **Pilot 3 — Guardrail-weakening check (F).** Reviewer/CI hook: noul over PR diff + changed
   files; high-confidence "yes" blocks merge pending human review (already aligned with
   required-conversation-resolution).
4. **Pilot 4 — Answer-adequacy scoring (H).** Score builder PR against acceptance criteria as a
   cheap pre-review signal; only escalate mid/low to the reviewer agent.

Model routing (C) can be derived from the complexity classification rather than a separate model.

## 4. Integration design (minimal, fits existing infra)

- **Service placement:** run the decider as a persistent dev-ops service, analogous to SigNoz
  (`dev-ops/signoz/`). A small compose service exposing port 8000, CPU-only to start
  (E4B or E2B; ~9–15 GB RAM for E4B, E2B smaller). Add to `dev-ops/environments.yaml`? Better:
  a dedicated compose file under `dev-ops/decider/` so deploys do not restart it.
- **Consumers:** factory agents already have `bash`/`curl` access in some modes; tick.sh and
  hooks can call `curl -s localhost:8000/v1/systemone`. Keep calls optional and
  fail-open (if the service is down, fall back to current LLM behavior) so the factory never
  blocks on it.
- **State payload:** issue title+body, PR diff summary, or acceptance-criteria text. Keep under
  the 4,096-token window; truncate/summarize large PRs.
- **Observability:** log every answer + probabilities (upstream Phase 8) to the factory JSONL
  stream / SigNoz for drift monitoring.
- **Secrets:** none new; model weights come from Hugging Face (public). Document in
  `dev-ops/.env.example` only if a token is needed for download.

## 5. Evaluation plan (measure before adopting)

Follow upstream's `skills/customize-decider` methodology, adapted to our data:

1. **Collect labels from history.** Our GitHub issues/PRs already carry labels (area, size,
   complexity, ready-for-build/needs-info) and reviewer outcomes — these are free labels, exactly
   the "final outcome is a better label than a first guess" case upstream recommends. Build
   `work/eval/*.jsonl` from closed issues/PRs (≥ 1,000 items per decision).
2. **Split by time** (most recent = eval), drop overlapping groups, freeze with `SHA256SUMS`.
3. **Baselines:** score every released model we can serve (E2B, E4B, maybe 12B on a GPU) on the
   same test half, plus our current "method" (the planner LLM's labels, or majority class).
   Record accuracy, ECE, latency, memory. Recalibrate the best candidate on our data (no training).
4. **Decision gate:** adopt only if a released model beats the majority-class baseline and the
   LLM's labels by more than eval noise, at acceptable latency/memory. Otherwise stop — upstream
   is explicit that a model below the majority class "has learned nothing useful".
5. **Training only if a gap remains** after rewording instructions and recalibrating. Cost:
   ~11 h on one RTX 3090 or ~1 h 10 min on 8× H100 with `FAST=1`. Requires GPU host approval.

To enable this, install upstream's `customize-decider` skill into our skill set:
add an entry to `dev-ops/skills.yaml` (repo `https://github.com/strands-labs/strands-decider.git`,
path `skills/customize-decider`) and run `dev-ops/scripts/request-skills.sh`. This skill is
plain Markdown and works with any agent that can read files and run shell commands — including
our OpenCode agents.

## 6. Risks and caveats

- **No labeled data yet.** Labels must be mined from history and audited; budget for labeling
  before any accuracy claim.
- **Domain mismatch.** Released models are trained on general decision tasks; our issue/PR text
  may differ. Recalibration helps; training may be needed.
- **Confidence calibration is the whole value.** If we ignore confidence and treat answers as
  deterministic, we lose the safety property and risk worse outcomes than the LLM.
- **Added infra + maintenance.** A new long-running service, model weights (~GBs), and a
  re-check plan each month (upstream Phase 8) for drift.
- **Over-automation risk.** Auto-applying labels/routing at mid confidence could misroute work;
  keep humans in the loop until measured.
- **Scope creep.** Product code must not depend on this; it is dev-process only, consistent with
  the `product/` vs `dev-ops/` split.

## 7. Recommendation

- **Do not integrate into product.** Keep it in `dev-ops/`.
- **Start with Pilot 1 (issue triage) only**, behind a fail-open flag, with the planner still
  owning label application. Run the evaluation (§5) on historical issues first; adopt only if the
  released model clears the majority-class + LLM-label baselines by more than noise.
- **Install the `customize-decider` skill** (skills.yaml entry) so agents can run the evaluation
  methodology without re-deriving it.
- **Defer training** until a pilot shows a gap that rewording + recalibration cannot close.
- **Revisit Pilots 2–4** only after Pilot 1 is measured and accepted.

## 8. Open questions for the owner

- Which GPU host (if any) is acceptable for a one-off evaluation/training run, and who approves
  the spend?
- Is auto-labeling infant issues acceptable, or should the decider only *suggest* labels in the
  plan comment?
- Should the decider service run on the dev server only, or also in QA/CI?
- Acceptable latency budget for a planning tick (current tick is hourly; a few seconds is fine).
