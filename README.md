# Agentic Production: Self-Healing Interoperability

An IRIS AI Hub agent that runs inside an IRIS interoperability production, repairs failed messages, and asks a person when it isn't sure.

Entry for the InterSystems Programming Contest "AI Agents in Interoperability Workflows". Implements the Ideas Portal idea [DPI-I-627: AI assisted debug](https://ideas.intersystems.com/ideas/DPI-I-627), with parts of [DPI-I-863](https://ideas.intersystems.com/ideas/DPI-I-863) (errors to a Workflow task list) and [DPI-I-574](https://ideas.intersystems.com/ideas/DPI-I-574) (AI analysis of errors).

## The problem

When a lab result fails in an interface engine, someone with HL7 and terminology skills has to open the message, find the cause and fix or resend it. Until then the result does not reach the clinician.

- Mapping one lab's test catalogue to LOINC takes about two to eight weeks, plus ongoing upkeep as assays change. A few hundred codes usually cover almost all of a lab's volume ([AHRQ HCUP](https://hcup-us.ahrq.gov/datainnovations/clinicaldata/RealTimeLOINCTranslationPoster.jsp)).
- About 4% of reviewed manual lab mappings in three large institutions had at least one error ([Lin et al., NLM](https://lhncbc.nlm.nih.gov/LHC-publications/PDF/pub2010042.pdf)).
- One bad message can block a queue and hold up the messages behind it.

An AI agent can do the first look much faster. But an agent that changes clinical messages on its own is not acceptable in healthcare. This project is about the second part: what the agent is allowed to do, and how that is enforced.

## What it does

A lab sends HL7 v2 ORU^R01 results. When a message fails validation, code lookup or delivery, the production hands it to a triage agent built with IRIS AI Hub (`%AI.Agent`). The agent reads the error and the message with read-only tools and returns one of five decisions:

| Decision | Example | What happens |
|---|---|---|
| AUTO_FIX | `2026-10-23 10:15` in a timestamp field | Applied automatically, only if it passes the checks below |
| MAP_CODE | local code `GLU-01` → LOINC `2345-7` | A person approves it in the Workflow inbox; the mapping is learned |
| RESEND | downstream timeout | Resent once |
| REJECT | segments out of order, wrong message type | Returned to the sender |
| ESCALATE | missing units, identity problems, anything unclear | A person decides |

The agent proposes. A deterministic business process (`AgenticProd.Process.Triage`) decides what actually happens.

## How it stays safe

- **Read-only agent.** Every tool the agent has is read-only. It runs as a dedicated IRIS user with SELECT-only grants, behind an authorization policy and an audit policy that logs every tool call.
- **Triage re-checks every fix.** An AUTO_FIX is applied only if Triage itself re-runs validation on a copy and it passes. The agent's own "validated" flag is never trusted. The original message is never changed; the fix creates a new message.
- **AUTO_FIX is a whitelist.** Only changes that keep the meaning the same can be applied without a person: a timestamp reformatted to the same instant, `<0.5` in a numeric field turned into the structured form `<^0.5`, an empty observation status copied from its order. Codes, values, units, flags and statuses always go to a person, even when the message would validate.
- **Patient identity is never changed.** Any fix touching PID-3, PID-5 or PID-7 is refused.
- **Prompt injection.** Message text reaches the model only inside marked data blocks. A deterministic scan flags instructions hidden in notes and text results; a flagged message is never auto-fixed and the reviewer sees the warning.
- **Budgets.** Per-message limits on tool calls and tokens, and a daily token budget. When a limit is hit the message goes to a person; it is never dropped.

## The learning loop

1. A result arrives with a local code nobody has mapped.
2. The agent searches a LOINC knowledge base (IRIS vector search with local FastEmbed embeddings), checks specimen, units and method, and proposes a code.
3. A reviewer approves it, or corrects it, in the Workflow inbox. The LOINC check digit is verified.
4. The mapping goes into the `LabCodeMap` lookup table and the original message is sent again.
5. The next message with that code goes straight through. No LLM call, no cost.

## Architecture

```
LabFileIn (HL7 file service)
   │
LabRouter ── valid ──► DTL (local code → LOINC) ──► NphiesOut (simulated receiver)
   │ error
   ▼
Triage ◄──► TriageAgent operation (%AI.Agent + skills + tools, runs as agentic_agent)
   │
   ├─ AUTO_FIX ─► re-check ─► new message ─► LabRouter
   ├─ RESEND / REJECT
   └─ MAP_CODE / ESCALATE ─► IntegrationSupport (EnsLib.Workflow) ─► approve ─► LabCodeMap
```

| Part | Classes |
|---|---|
| Agent | `Agent.TriageAgent` (declarative `%AI.Agent`), skills `Skill.HL7Repair`, `Skill.CodeMapping` |
| Tools | `Tools.Base` (format-neutral), `Tools.HL7`, `Tools.Mapping` |
| Policies | `Policy.ReadOnly`, `Policy.Audit`, `Policy.InjectionGuard` |
| Production | `Process.LabRouter`, `Process.Triage`, `Operation.Agent`, `Operation.NphiesOut`, `DTL.LabToNphies` |
| Records | `Data.DecisionLog`, `Data.Usage`, `Data.ToolCall`, `Data.PriceTable`, `Data.EvalRun`, `Data.EvalResult` |

The core is format-neutral: error classes, decisions, Triage and the stores do not depend on HL7. HL7 v2 is the first format; fix checking is looked up per format.

## Install

You need Docker and access to the IRIS AI Hub early access image (build 154).

```bash
git clone https://github.com/mwaseem75/iris-agentic-production.git
cd iris-agentic-production

# load the AI Hub EAP image and tag it with the name the Dockerfile expects
docker load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker tag <loaded image name> irishealth-community:2026.3.0AI.154.0

cp .env.example .env        # add OPENAI_API_KEY for live mode; replay mode needs no key
docker compose up -d --build
```

Setup runs on install: it seeds the price table and `LabCodeMap`, builds the LOINC knowledge base, creates the agent role and user, and sets up the Workflow role and a demo reviewer.

- Management Portal: http://localhost:52773/csp/sys/UtilHome.csp (`SuperUser` / `SYS`)
- Production: Interoperability → IRISAPP → `AgenticProd.Production`
- Reviewer inbox: Interoperability → Workflow Inbox, log in as `reviewer` / `Review-Demo-2026` (demo only)

## Try it

Open a terminal in the container:

```bash
docker compose exec iris iris session iris -U IRISAPP
```

```objectscript
// one broken message: bad timestamp, fixed automatically
do ##class(AgenticProd.Demo).SendCase("05")

// unmapped glucose code: approve it in the Workflow inbox, then send it again
do ##class(AgenticProd.Demo).SendCase("01")
do ##class(AgenticProd.Demo).SendCase("01", "MSG90001")

// replay the recorded evaluation: no API key, no cost
do ##class(AgenticProd.Eval.Runner).Run("gpt-4o-mini", "replay demo", "all", "replay")
```

To start a demo or a recording from a clean state:

```objectscript
do ##class(AgenticProd.Demo).Reset()
```

It deletes all live (non-eval) decisions, usage, tool calls, spans and Workflow tasks, purges
every production message, sets LabCodeMap back to the seed codes and empties `data/in`,
`data/out`, `data/out-fhir` and `data/rejected`. It does not ask first. Eval runs, their results
and the recorded runs that replay uses are kept.

Then open Visual Trace for the session to see each step: router, Triage, every agent tool call, the decision and its cost.

## FHIR output

Every lab result that passes LabRouter also goes out as FHIR R4, built with the converters that
ship with IRIS for Health: HL7 v2 → SDA3 (`HS.Gateway.HL7.HL7ToSDA3`) → FHIR R4 bundle
(`HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR`). `NphiesFHIROut` adds the LOINC coding from
LabCodeMap to each Observation (the local code stays as a second coding), checks every resource
against the R4 base structure and every Observation against US Core `us-core-observation-lab`
3.1.0, which stands in for the NPHIES profiles. Valid bundles land in `data/out-fhir/`. An invalid
bundle is not sent: its issues go to Triage as a `FHIR` problem, and until there is a FHIR fix
checker Triage hands it to a person without calling the agent. LabRouter's `FHIROutput` setting
turns this off; the HL7 output to `data/out/` is unchanged.

## Evaluation

60 synthetic test cases in [`eval/cases`](eval/cases): normal errors, look-alike LOINC codes (serum vs blood vs urine, fasting, high-sensitivity, calculated), identity traps, structure and routing errors, a simulated timeout, prompt injection attempts and valid controls. Each case lists the expected decision, the other acceptable decisions, and the decisions that would be unsafe.

The most important number is **unsafe_final**: how often the system carried out an unsafe decision. It is counted separately from **unsafe_agent**, how often the model proposed one.

<!-- TODO 5.3: fill in from Data.EvalRun -->

| Model | Accuracy | Mapping accuracy | unsafe_agent | unsafe_final | Cost per message | p95 seconds |
|---|---|---|---|---|---|---|
| gpt-4o-mini | | | | | | |
| gpt-5-nano | | | | | | |

## Observability

Every agent run records prompt, completion, reasoning and cache tokens from the AI Hub session stats, with cost from `Data.PriceTable`. Every tool call is logged by the audit policy, including the verdict of each `validate_fix`. Agent sessions are saved, so any run can be opened later or replayed.

- **Dashboard** (`/agenticprod`, reviewer login): KPI tiles, recent decisions, eval runs and an **Agent metrics** section: tokens by type per model, agent latency p50/p95, step durations from spans (router, agent, Triage), tool calls per tool with average time, `validate_fix` results, the decision mix per hour, approval wait time, and LLM calls saved by learned mappings. Live traffic by default; tick "Include eval runs" to add eval messages. The same numbers are at `/agenticprod/api/metrics/summary`.
- **Traces stored in IRIS**: every failed message gets one trace (router check, agent run, each tool call, the Triage decision, the review) in `Data.Span`. Click a row in Recent decisions to see the message's story in plain steps, a timeline of its spans and the masked message.
- **Prometheus / Grafana**: `/api/monitor/metrics` (IRIS SAM) also serves `gen_ai_client_token_usage{model,type}`, `gen_ai_client_operation_duration_seconds{model}` (summary, p50/p95), `agentic_decisions_total{decision,outcome}`, `agentic_tool_calls_total{tool}`, `agentic_unsafe_blocked_total`, `agentic_llm_calls_saved_total` and `agentic_approval_waiting` (`AgenticProd.Monitor.Metrics`, registered by `Setup`). These are totals over the stored tables, eval traffic included.
- **Visual Trace**: each decision links to the message session in the Management Portal.
- **Jaeger (optional)**: `docker compose --profile observability up -d`, then turn on `TracingEnabled` on the Triage item to also export spans over OTLP; Jaeger UI at http://localhost:16686.

Charts use [Apache ECharts](https://echarts.apache.org/) 5.5.1, vendored in `web/vendor/echarts` with its LICENSE and NOTICE (Apache License 2.0). Nothing is loaded from a CDN.

## Limits

- HL7 v2 lab results in. FHIR R4 goes out, but the agent cannot repair FHIR yet.
- The LOINC knowledge base is a 46-code demonstration subset. See [`kb/LOINC_NOTICE.md`](kb/LOINC_NOTICE.md).
- IRIS AI Hub is pre-release (build 154). A few workarounds are noted in the code.
- All data is synthetic. No real patients.

## Licence

MIT. LOINC content is © Regenstrief Institute, Inc., used under the LOINC licence.
