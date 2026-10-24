/// HL7 v2 repair skill for the triage agent. Instructions only; the tools are in
/// AgenticProd.Tools.HL7 (TOOLS). Define no methods here: anything defined would become a tool.
Class AgenticProd.Skill.HL7Repair Extends %AI.Agent.Skill
{

Parameter TOOLS = "AgenticProd.Tools.HL7";

XData SUMMARY [ MimeType = text/yaml ]
{
name: hl7-repair
description: Load when the failed message is HL7 v2 (Format HL7v2, or text with MSH/PID/OBR/OBX segments). Adds get_segment, search_interface_spec and validate_fix, and the rules for proposing and proving an HL7 v2 fix.
tags:
  - hl7
  - repair
  - validation
}

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# HL7 v2 repair

Use these steps for a failed HL7 v2 message, after `get_error_events`.

## Steps
1. `get_segment` for each segment named in the errors (e.g. `OBX(1)`). Read the current value
   of every field you plan to change.
2. `search_interface_spec` for the rule behind the error (e.g. `TS`, `0123`, `SN`, `PID-3`).
   Base the fix on the spec, not on guesses.
3. If a fix is possible, call `validate_fix` with the exact steps you will put in `fix`,
   each with `path`, `from` (the current value) and `to`.

## Deciding
- `AUTO_FIX` only after `validate_fix` returned PASS for the exact same steps you answer
  with. Then set `"validated": true`. If you change any step after the PASS, call
  `validate_fix` again.
- FAIL: read the remaining errors, adjust the fix and validate again, or choose another
  decision with `"validated": false`.
- PASS_NEEDS_REVIEW: the message would validate, but the fix changes meaning (a code, result
  value, unit, flag or status). Never `AUTO_FIX`: answer `ESCALATE` with the fix and
  `"validated": false` so the reviewer sees it, or `MAP_CODE` when the change is a local code
  to LOINC mapping. AUTO_FIX only covers a timestamp reformatted to the same instant, OBX-2
  NM to SN keeping comparator and number, and an empty OBX-11 copied from its OBR-25.
- REFUSED: the fix touches patient identity (PID-3, PID-5, PID-7). Answer
  `error_class` `IDENTITY_ISSUE`, `decision` `ESCALATE`, `fix` `[]`.
- Segments out of order or missing required segments: `STRUCTURE_ERROR` with `REJECT`.
  Never reorder, add or remove segments.
- Never drop a comparator from a result. A value like `<0.5` becomes OBX-2 `SN` and
  OBX-5 `<^0.5`, never `0.5`.
- A date or time you cannot convert without guessing (e.g. `03/04/2026`: day and month
  unclear, or a missing year) is `ESCALATE`. Only reformat when the instant stays the same.
- A value the spec says cannot be guessed (e.g. OBR-25 result status) is `ESCALATE`.
}

}
