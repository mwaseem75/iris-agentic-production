/// Local lab code to LOINC mapping skill for the triage agent. Instructions only; the tools are in
/// AgenticProd.Tools.Mapping (TOOLS). Define no methods here: anything defined would become a tool.
Class AgenticProd.Skill.CodeMapping Extends %AI.Agent.Skill
{

Parameter TOOLS = "AgenticProd.Tools.Mapping";

XData SUMMARY [ MimeType = text/yaml ]
{
name: code-mapping
description: Load when the error is UNMAPPED_CODE (a local test code has no LOINC mapping). Adds lookup_code, search_loinc and similar_past_mappings, and the rules for proposing a mapping that a person approves.
tags:
  - loinc
  - mapping
  - terminology
}

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Local code to LOINC mapping

Use these steps when a local test code (OBX-3.1) has no LOINC mapping.

## Steps
1. `get_failed_message`. From it note OBX-3.1 (local code), OBX-3.2 (test name), OBX-6
   (units) and SPM-4 (specimen type, e.g. Serum specimen, Blood specimen); if there is no
   SPM, use OBR-15.
2. `lookup_code` with the local code and the sender (MSH-3). If it is already mapped, the
   failure is something else: say so and `ESCALATE`.
3. `similar_past_mappings` with the local code and the test name. An approved mapping for the
   same code is strong evidence.
4. `search_loinc` with the test name, specimen and units.

## Choosing
- Use OBX-3 text, OBX-6 units and the specimen together. The candidate's `system` must match
  the specimen (Ser/Plas for serum or plasma, Bld for blood, Urine for urine) and its `units`
  must agree with OBX-6. A high score with the wrong specimen or units is wrong.
- If two candidates fit equally well, do not pick one: `ESCALATE` and list both in
  `evidence`. Typical cases: troponin I vs troponin T, standard vs high-sensitivity method,
  fasting vs random, serum vs blood when the specimen is not given.
- If OBX-3.2 and OBX-17 name no method, choose a candidate with method none. Only pick a
  method-specific code when the message names that method.
- If no candidate fits, `ESCALATE`.

## Deciding
- A good single candidate: `decision` `MAP_CODE`, `error_class` `UNMAPPED_CODE`, `mapping`
  with `local_code`, `loinc` and `display` (the candidate's display), `fix` `[]`,
  `"validated": false`. A person approves every mapping before it is used.
- Never answer `AUTO_FIX` for a code. Never put a code change in `fix`.
- `evidence` quotes OBX-3, OBX-6, the specimen and the chosen candidate's system and units.
}

}
