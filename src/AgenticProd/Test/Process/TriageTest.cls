Include Ensemble

/// Process.Triage action matrix with stub decisions on eval cases. Calls Plan, Review and
/// ApplyMapping directly, no LLM. Only TestLearningLoop01 sends, into the running production.
Class AgenticProd.Test.Process.TriageTest Extends AgenticProd.Test.Case
{

/// Request Source of the DecisionLog rows these tests write, so cleanup finds them.
Parameter TESTSOURCE = "AgenticProd.Test.Process";

/// AgentSessionId prefix of the fake search_loinc ToolCall rows the grounding tests write.
Parameter TESTSESSION = "TESTGROUND-";

Method TestAutoFixApplied05()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.9, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do $$$AssertEquals(tOutcome, "APPLIED", tFinal.Reason)
	Do $$$AssertEquals(tFinal, tDecision)
	If '$$$AssertTrue($IsObject(tFixed), "new message built") Quit
	Do ##class(AgenticProd.Tools.Base).OpenBody(tRequest.HeaderId, .tOriginal)
	Do $$$AssertNotEquals(tFixed.%Id(), "", "new message saved")
	Do $$$AssertNotEquals(tFixed.%Id(), tOriginal.%Id(), "new message, not the original")
	Do $$$AssertEquals(tFixed.GetValueAt("4:14"), "202610231015", "new message has the fix")
	Do $$$AssertEquals(tOriginal.GetValueAt("4:14"), "2026-10-23 10:15", "original unchanged")
	Do ##class(EnsLib.HL7.Message).%DeleteId(tFixed.%Id())
}

/// AUTO_FIX switched off for the class on the Settings tab: a valid, confident fix still goes to a person.
Method TestAutoFixDisabledInSettings05()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Set tTriage = ..Triage()
	Set tTriage.AutoFixDisabled = "MISSING_FIELD,BAD_FORMAT"
	Do $$$AssertStatusOK(tTriage.Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "auto-fix disabled in Settings")
	Do $$$AssertEquals(tFixed, "", "nothing built")
}

Method TestLowConfidenceEscalates05()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.6, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "below AutoFixThreshold")
	Do $$$AssertEquals(tFixed, "", "nothing built")
	// The reviewer still sees the proposed fix
	Do $$$AssertEquals(tFinal.Fix.GetAt(1).ToValue, "202610231015")
}

/// The agent claims validated=1, but its fix does not pass Triage's own re-check.
Method TestAgentLiedEscalates05()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1, "OBX(1):14", "2026-10-23 10:15", "2026/10/23 10:15")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "re-check of the fix did not pass")
	Do $$$AssertEquals(tFixed, "")
	Do ##class(AgenticProd.Tools.Base).OpenBody(tRequest.HeaderId, .tOriginal)
	Do $$$AssertEquals(tOriginal.GetValueAt("4:14"), "2026-10-23 10:15", "original unchanged")
}

Method TestIdentityFixEscalates11()
{
	Do $$$AssertStatusOK(..Case("11", "BAD_FORMAT", .tRequest))
	// Mislabelled as BAD_FORMAT on purpose: the PID-3 path alone must stop it
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.99, 1, "PID(1):3.4", "", "SIMHOSP")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "protected identity field")
	Do $$$AssertEquals(tFixed, "")
}

Method TestResendOnlyOnce15()
{
	Do $$$AssertStatusOK(..Case("15", "TRANSIENT", .tRequest))
	Set tTriage = ..Triage()
	Set tDecision = ..Stub("RESEND", "TRANSIENT", 0.8, 0)
	Do $$$AssertStatusOK(tTriage.Plan(tRequest, tDecision, .tFinal, .tOutcome))
	Do $$$AssertEquals(tOutcome, "RESENT")
	Do $$$AssertStatusOK(##class(AgenticProd.Data.DecisionLog).Record(tRequest, tFinal, , tOutcome))

	Do $$$AssertStatusOK(tTriage.Plan(tRequest, ..Stub("RESEND", "TRANSIENT", 0.8, 0), .tFinal, .tOutcome))
	Do ..AssertDowngraded(tFinal, tOutcome, "RESEND", "already resent once")
}

Method TestResendNeedsTransient()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, ..Stub("RESEND", "BAD_FORMAT", 0.9, 0), .tFinal, .tOutcome))
	Do ..AssertDowngraded(tFinal, tOutcome, "RESEND", "only for TRANSIENT")
}

Method TestReject13And01()
{
	Do $$$AssertStatusOK(..Case("13", "STRUCTURE_ERROR", .tRequest))
	Set tDecision = ..Stub("REJECT", "STRUCTURE_ERROR", 0.9, 0)
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome))
	Do $$$AssertEquals(tOutcome, "REJECTED")
	Do $$$AssertEquals(tFinal.Decision, "REJECT")
	Set tTriage = ..Triage()
	Do $$$AssertStatusOK(tTriage.WriteRejected(tRequest, tFinal))
	Set tBase = ##class(%File).NormalizeFilename("rejected_"_tRequest.HeaderId, tTriage.RejectPath)
	For tExt = ".msg", ".reason.txt" {
		Do $$$AssertTrue(##class(%File).Exists(tBase_tExt), "wrote "_tBase_tExt)
		Do ##class(%File).Delete(tBase_tExt)
	}

	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, ..Stub("REJECT", "UNMAPPED_CODE", 0.9, 0), .tFinal, .tOutcome))
	Do ..AssertDowngraded(tFinal, tOutcome, "REJECT", "only for STRUCTURE_ERROR or ROUTING")
}

Method TestMapCodeAndEscalateGoToApproval()
{
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.99, 0)
	Set tDecision.Mapping.LocalCode = "GLU-01", tDecision.Mapping.Loinc = "2345-7"
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do $$$AssertEquals(tOutcome, "SENT_FOR_APPROVAL")
	Do $$$AssertEquals(tFinal.Decision, "MAP_CODE", "high confidence still needs approval")
	Do $$$AssertEquals(tFixed, "")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, ..Stub("ESCALATE", "OTHER", 0.2, 0), .tFinal, .tOutcome))
	Do $$$AssertEquals(tOutcome, "SENT_FOR_APPROVAL")
}

/// Hard rule 5 whitelist: meaning-preserving fixes on 05, 06, 08 and 10 are applied.
Method TestWhitelistApplied()
{
	Set tCases = $LISTBUILD(
		$LISTBUILD("05", "OBX(1):14", "2026-10-23 10:15", "202610231015"),
		$LISTBUILD("06", "OBR(1):7", "23/10/2026 08:30", "202610230830"),
		$LISTBUILD("08", "OBX(1):2", "NM", "SN", "OBX(1):5", "<0.5", "<^0.5"),
		$LISTBUILD("10", "OBX(1):11", "", "F"))
	For i = 1:1:$LISTLENGTH(tCases) {
		Set tCase = $LIST(tCases, i)
		Do $$$AssertStatusOK(..Case($LIST(tCase, 1), "BAD_FORMAT", .tRequest))
		Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.9, 1)
		For s = 2:3:$LISTLENGTH(tCase) Do ..AddStep(tDecision, $LIST(tCase, s), $LIST(tCase, s + 1), $LIST(tCase, s + 2))
		Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
		Do $$$AssertEquals(tOutcome, "APPLIED", "case "_$LIST(tCase, 1)_": "_tFinal.Reason)
		Do:$IsObject(tFixed) ##class(EnsLib.HL7.Message).%DeleteId(tFixed.%Id())
	}
}

/// Fixes that validate but change meaning: ESCALATE, proposal kept for the reviewer.
Method TestOffWhitelistEscalates()
{
	Set tCases = $LISTBUILD(
		$LISTBUILD("10", "OBX(1):11 must copy OBR-25", "OBX(1):11", "", "P"),
		$LISTBUILD("01", "code", "OBX(1):3", "GLU-01^Glucose^L", "2345-7^Glucose^LN"),
		$LISTBUILD("07", "unit", "OBX(1):6", "", "mmol/L"),
		$LISTBUILD("09", "status", "OBR(1):25", "X1", "F"),
		$LISTBUILD("05", "value", "OBX(1):14", "2026-10-23 10:15", "202610231015", "OBX(1):5", "139", "145"))
	For i = 1:1:$LISTLENGTH(tCases) {
		Set tCase = $LIST(tCases, i)
		Do $$$AssertStatusOK(..Case($LIST(tCase, 1), "BAD_FORMAT", .tRequest))
		Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1)
		For s = 3:3:$LISTLENGTH(tCase) Do ..AddStep(tDecision, $LIST(tCase, s), $LIST(tCase, s + 1), $LIST(tCase, s + 2))
		Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
		Do $$$AssertEquals(tOutcome, "DOWNGRADED:AUTO_FIX", "case "_$LIST(tCase, 1)_" "_$LIST(tCase, 2))
		Do $$$AssertTrue(tFinal.Reason [ "not auto-fixable", tFinal.Reason)
		Do $$$AssertEquals(tFinal.Fix.Count(), tDecision.Fix.Count(), "proposed fix kept")
		Do $$$AssertEquals(tFixed, "", "nothing built")
	}
}

/// A body Triage built for an APPLIED fix is recognised when it fails again (loop guard).
Method TestFixedByTriage()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.9, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do $$$AssertEquals(tOutcome, "APPLIED")
	Do $$$AssertNotTrue(##class(AgenticProd.Process.Triage).FixedByTriage(tRequest.HeaderId), "original body is not a Triage fix")
	Do $$$AssertStatusOK(##class(AgenticProd.Data.DecisionLog).Record(tRequest, tFinal, , tOutcome, tFixed))

	// The fixed message arrives back under a new header, as it would from LabRouter
	Set tHeader = ##class(Ens.MessageHeader).%New()
	Set tHeader.SourceConfigName = ##class(AgenticProd.Test.Tools.HL7Test).#TESTSOURCE
	Set tHeader.MessageBodyClassName = $CLASSNAME(tFixed), tHeader.MessageBodyId = tFixed.%Id()
	Do $$$AssertStatusOK(tHeader.%Save())
	Do $$$AssertTrue(##class(AgenticProd.Process.Triage).FixedByTriage(tHeader.%Id()), "fixed body recognised")
	// Body IDs repeat across namespaces: another namespace's fix row must not match
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE AgenticProd_Data.DecisionLog SET Namespace = 'OTHERNS' WHERE FixedBodyId = ? AND FixedBodyClass = ?", tFixed.%Id(), $CLASSNAME(tFixed))
	Do $$$AssertNotTrue(##class(AgenticProd.Process.Triage).FixedByTriage(tHeader.%Id()), "fix row from another namespace ignored")
}

/// A fix that would pass on its own is still refused when the message text was flagged.
Method TestFlaggedNeverAutoFix()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Do tRequest.Flags.Insert("NTE(1):3: system note, ai agent")
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.99, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome, .tFixed))
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "suspicious instruction in the message text (NTE(1):3)")
	Do $$$AssertEquals(tFixed, "", "nothing built")
	Do $$$AssertEquals(tFinal.Evidence.GetAt(tFinal.Evidence.Count()), "suspicious instruction in NTE(1):3: system note, ai agent")

	// Other decisions go ahead, with the flag in the evidence for the reviewer
	Do $$$AssertStatusOK(..Case("18", "UNMAPPED_CODE", .tRequest))
	Do tRequest.Flags.Insert("NTE(1):3: system note")
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.9, 0)
	Set tDecision.Mapping.LocalCode = "CHOL-S", tDecision.Mapping.Loinc = "2093-3"
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome))
	Do $$$AssertEquals(tOutcome, "SENT_FOR_APPROVAL")
	Do $$$AssertEquals(tFinal.Evidence.GetAt(1), "suspicious instruction in NTE(1):3: system note")
}

/// MAP_CODE task: approve writes LabCodeMap (reviewer's correction wins), reject and a bad
/// check digit write nothing.
Method TestReviewMapCode01()
{
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Do tRequest.Flags.Insert("NTE(1):3: system note")
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.9, 0)
	Set tDecision.Mapping.LocalCode = "GLU-01", tDecision.Mapping.Loinc = "2345-7", tDecision.Mapping.Display = "Glucose [Mass/volume] in Serum or Plasma"
	Do tDecision.Evidence.Insert("search_loinc: 2345-7")
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).FromDecision(tRequest, tDecision)
	Do $$$AssertEquals(tTask.%Actions, "Approve,Reject")
	Do $$$AssertEquals(tTask.%FormFields, "Loinc,Note")
	Do $$$AssertEquals(tTask.%FormValues.GetAt("Loinc"), "2345-7")
	Do $$$AssertEquals(tTask.LocalCode_"|"_tTask.Display, "GLU-01|Glucose [Mass/volume] in Serum or Plasma")
	Do $$$AssertEquals(tTask.Flags.GetAt(1), "NTE(1):3: system note")
	Do $$$AssertEquals(tTask.Evidence.GetAt(1), "search_loinc: 2345-7")
	Do $$$AssertStatusOK(tTask.%Save(), "task saves as a message")
	Do ##class(AgenticProd.Msg.ApprovalTask).%DeleteId(tTask.%Id())

	Do ..RemoveTestMappings()
	Set tLog = ..Reviewed(tRequest, tDecision, "Reject", "2339-0", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_REJECTED")
	Do $$$AssertEquals(tLog.Loinc, "2345-7", "rejected: proposal logged as it was")
	Do $$$AssertEquals(..Mapped("GLU-01"), "", "rejected: no LabCodeMap entry")
	Do $$$AssertEquals(tResend, "")

	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "2345-8", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_BAD_LOINC")
	Do $$$AssertTrue(tLog.ReviewNote [ "wrong check digit (expected 7)", tLog.ReviewNote)
	Do $$$AssertEquals(..Mapped("GLU-01"), "", "bad LOINC: no LabCodeMap entry")
	Do $$$AssertEquals(tResend, "", "bad LOINC: message stays failed")

	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "2339-0", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "APPROVED")
	Do $$$AssertEquals(tLog.Reviewer, "reviewer")
	Do $$$AssertNotEquals(tLog.ReviewedAt, "")
	Do $$$AssertEquals(tLog.Loinc, "2339-0", "reviewer's correction")
	Do $$$AssertEquals(..Mapped("GLU-01"), "2339-0^Glucose [Mass/volume] in Blood", "corrected code, display from the subset")
	Do $$$AssertEquals(tResend, tRequest.HeaderId, "original message resent")
	Do $$$AssertEquals(tFixed, "")

	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Loinc, "2345-7", "empty form field keeps the proposal")
	Do $$$AssertEquals(..Mapped("GLU-01"), "2345-7^Glucose [Mass/volume] in Serum or Plasma")
	Do ..RemoveTestMappings()
}

/// Valid codes outside the LOINC subset: the agent's display only if the code is unchanged.
Method TestMappingOutsideSubset()
{
	Do ..RemoveTestMappings()
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).%New()
	Set tTask.LocalCode = "GLU-01", tTask.Loinc = "12345-5", tTask.Display = "agent display"
	Do $$$AssertStatusOK(##class(AgenticProd.Process.Triage).ApplyMapping(tTask, "12345-5", .tWhy))
	Do $$$AssertEquals(tWhy, "")
	Do $$$AssertEquals(..Mapped("GLU-01"), "12345-5^agent display", "unchanged: agent's display")
	Set tTask.Loinc = "2345-7"
	Do $$$AssertStatusOK(##class(AgenticProd.Process.Triage).ApplyMapping(tTask, "12345-5", .tWhy))
	Do $$$AssertEquals(..Mapped("GLU-01"), "12345-5^", "changed by the reviewer: no display")
	Do ..RemoveTestMappings()
}

Method TestLoincCheckDigit()
{
	For tCode = "2345-7", "2339-0", "2093-3", "17861-6", "630-4", "100000-9", "1234567-4" {
		Do $$$AssertEquals(##class(AgenticProd.Process.Triage).LoincProblem(tCode), "", tCode_" valid")
	}
	For tCode = "2345-8", "2345", "2345-77", "123456-1", "12345678-0", "GLU-01", "" {
		Do $$$AssertNotEquals(##class(AgenticProd.Process.Triage).LoincProblem(tCode), "", "'"_tCode_"' refused")
	}
}

/// Correct MAP_CODE for case 01 with real quotes: every grounding check passes, Triage goes on as before.
Method TestGroundingCorrect01()
{
	Set tDecision = ..MapStub("01", "GLU-01", "2345-7", "2345-7,2339-0,2350-7", .tRequest)
	Do tDecision.Evidence.Insert("OBX-3 'GLU-01^Glucose^L' has no LabCodeMap entry")
	Do tDecision.Evidence.Insert("SPM-4 ""Serum specimen"" and OBX-6 'mg/dL' fit 2345-7")
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	If '$$$AssertTrue($IsObject(tGround), "grounding ran") Quit
	Do $$$AssertTrue(tGround.grounded, tGround.summary)
	Do $$$AssertEquals(tGround.failed, "")
	Do $$$AssertEquals(tGround.checks.%Size(), 7, "kb, search, revoked, local code, specimen, units, quotes")
	Do $$$AssertEquals(tOutcome, "SENT_FOR_APPROVAL")
	Do $$$AssertEquals(tFinal, tDecision, "decision unchanged")
}

Method TestGroundingLoincNotInKB01()
{
	// 12345-5 has a valid check digit but is not in the LOINC subset
	Set tDecision = ..MapStub("01", "GLU-01", "12345-5", "12345-5,2345-7", .tRequest)
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "loinc_in_kb")
	Do ..AssertDowngraded(tFinal, tOutcome, "MAP_CODE", "ungrounded: loinc_in_kb")
	Do $$$AssertEquals(tFinal.Mapping.Loinc, "12345-5", "proposal kept for the reviewer")
}

Method TestGroundingNotFromSearch01()
{
	Set tDecision = ..MapStub("01", "GLU-01", "2345-7", "2339-0,2350-7", .tRequest)
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "loinc_from_search")
	Do ..AssertDowngraded(tFinal, tOutcome, "MAP_CODE", "ungrounded: loinc_from_search")
	// No search_loinc call at all in the session
	Set tDecision = ..MapStub("01", "GLU-01", "2345-7", "", .tRequest)
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "loinc_from_search")
	Do $$$AssertTrue(tGround.summary [ "no search_loinc result", tGround.summary)
}

/// Specimen: serum message mapped to a blood code. Units: mmol/L potassium mapped to mg/dL glucose.
Method TestGroundingSpecimenUnits()
{
	Set tDecision = ..MapStub("01", "GLU-01", "2339-0", "2339-0,2345-7", .tRequest)
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "specimen", tGround.summary)
	Do ..AssertDowngraded(tFinal, tOutcome, "MAP_CODE", "Bld")

	Set tDecision = ..MapStub("04", "K-S", "2345-7", "2345-7", .tRequest)
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "units", tGround.summary)
	Do ..AssertDowngraded(tFinal, tOutcome, "MAP_CODE", "mmol/L")
}

Method TestGroundingFakeQuote01()
{
	Set tDecision = ..MapStub("01", "GLU-01", "2345-7", "2345-7", .tRequest)
	Do tDecision.Evidence.Insert("OBX-5 reads 'glucose 412 mg/dL', it doesn't fit urine")
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "evidence_quotes")
	Do $$$AssertTrue(tGround.summary [ "unverified quote: 'glucose 412 mg/dL'", tGround.summary)
	Do $$$AssertNotTrue(tGround.summary [ "t fit", "an apostrophe is not a quote")
	Do ..AssertDowngraded(tFinal, tOutcome, "MAP_CODE", "unverified quote")
}

/// warn records and shows the failure but Triage still acts; enforce stops the same AUTO_FIX
/// before a fixed copy is built; a wrong "from" is caught as fix_from; off checks nothing.
Method TestGroundingWarnActs05()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do tDecision.Evidence.Insert("OBX-14 was '31/02/2026 10:15'")
	Set tTriage = ..Triage()
	Set tTriage.GroundingStrictness = "warn"
	Set tGround = ..Grounded(tTriage, tRequest, tDecision, .tFinal, .tOutcome, .tFixed)
	Do $$$AssertEquals(tGround.failed, "evidence_quotes")
	Do $$$AssertEquals(tGround.strictness, "warn")
	Do $$$AssertEquals(tOutcome, "APPLIED", "warn mode acts")
	Do $$$AssertTrue(tFinal.Evidence.GetAt(tFinal.Evidence.Count()) [ "ungrounded (warn mode): evidence_quotes")
	Do:$IsObject(tFixed) ##class(EnsLib.HL7.Message).%DeleteId(tFixed.%Id())

	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do tDecision.Evidence.Insert("OBX-14 was '31/02/2026 10:15'")
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome, .tFixed)
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "ungrounded: evidence_quotes")
	Do $$$AssertEquals(tFixed, "", "enforce: no fixed copy built")

	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.95, 1, "OBX(1):14", "2026-10-23 10:16", "202610231016")
	Set tGround = ..Grounded(..Triage(), tRequest, tDecision, .tFinal, .tOutcome, .tFixed)
	Do $$$AssertEquals(tGround.failed, "fix_from")
	Do $$$AssertTrue(tGround.summary [ "message has '2026-10-23 10:15'", tGround.summary)
	Do ..AssertDowngraded(tFinal, tOutcome, "AUTO_FIX", "ungrounded: fix_from")

	Set tTriage = ..Triage()
	Set tTriage.GroundingStrictness = "off"
	Set tGround = ..Grounded(tTriage, tRequest, tDecision, .tFinal, .tOutcome, .tFixed)
	Do $$$AssertEquals(tGround, "", "off: not checked")
}

/// Approve writes a LearnedMapping row; revoke removes the LabCodeMap entry, sends a review task
/// per routed message and blocks learning the pair again without a reviewer's note.
Method TestLearnedMappingApproveRevoke01()
{
	Do ..RemoveTestMappings()
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.9, 0)
	Set tDecision.Mapping.LocalCode = "GLU-01", tDecision.Mapping.Loinc = "2345-7"
	Do tDecision.Evidence.Insert("search_loinc: 2345-7")
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "APPROVED")
	Set tRowId = ##class(AgenticProd.Data.LearnedMapping).ActiveId("GLU-01")
	If '$$$AssertNotEquals(tRowId, "", "LearnedMapping row written") Quit
	Set tRow = ##class(AgenticProd.Data.LearnedMapping).%OpenId(tRowId)
	Do $$$AssertEquals(tRow.Origin_"|"_tRow.Loinc_"|"_tRow.Reviewer_"|"_tRow.DecisionLogId, "Approved|2345-7|reviewer|"_tLog.%Id())
	Do $$$AssertEquals(tRow.Evidence, "search_loinc: 2345-7")
	Do $$$AssertEquals(tRow.Warning, "", "in the KB: no warning")

	// A second message that went out on the learned mapping
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRouted))
	Set tSaved = ##class(AgenticProd.Data.SavedCall).%New()
	Set tSaved.HeaderId = tRouted.HeaderId, tSaved.LocalCodes = "GLU-01"
	Do $$$AssertStatusOK(tSaved.%Save())
	Set tHeaders = ##class(AgenticProd.Settings.Store).RoutedWith("GLU-01", tRow.ApprovedAt, tLog.%Id())
	Do $$$AssertEquals(tHeaders.%ToJSON(), "["_tRequest.HeaderId_","_tRouted.HeaderId_"]")

	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).RevokeMapping(tRowId, " ", .tNote), "reason required")
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).RevokeMapping(tRowId, "test: wrong specimen", .tNote))
	Do $$$AssertEquals(..Mapped("GLU-01"), "", "LabCodeMap entry removed")
	Set tRow = ##class(AgenticProd.Data.LearnedMapping).%OpenId(tRowId)
	Do $$$AssertEquals(tRow.Status_"|"_tRow.RevokedBy_"|"_tRow.RevokeReason, "Revoked|"_$USERNAME_"|test: wrong specimen")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.SettingsAudit WHERE Scope = 'memory' AND Item = 'GLU-01' AND NewValue %STARTSWITH 'revoked: test: wrong specimen'")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.N, 1, "revoke in the change log")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).RevokeMapping(tRowId, "again", .tNote2), "already revoked")
	If ##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertTrue(tNote [ "2 review task(s) sent", tNote)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Msg.ApprovalTask WHERE Reason %STARTSWITH 'mapping revoked, please review' AND HeaderId IN (?, ?)", tRequest.HeaderId, tRouted.HeaderId)
		Do tRS.%Next()
		Do $$$AssertEquals(tRS.N, 2, "one review task per routed message")
	} Else {
		Do $$$AssertTrue(tNote [ "not sent", tNote)
	}

	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_REVOKED", "revoked pair needs a note")
	Do $$$AssertEquals(..Mapped("GLU-01"), "")
	Do $$$AssertEquals(tResend, "")
	Set tGround = ..Grounded(..Triage(), tRequest, ..MapStub("01", "GLU-01", "2345-7", "2345-7", .tRequest2), .tFinal, .tOutcome)
	Do $$$AssertEquals(tGround.failed, "not_revoked", "the gate flags a revoked mapping too")

	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed, .tResend, "lab confirmed serum")
	Do $$$AssertEquals(tLog.Outcome, "APPROVED", "learned again with a note")
	Set tRow = ##class(AgenticProd.Data.LearnedMapping).%OpenId(##class(AgenticProd.Data.LearnedMapping).ActiveId("GLU-01"))
	Do $$$AssertTrue(tRow.Warning [ "reviewer note: lab confirmed serum", tRow.Warning)

	// Reviewer's correction outside the KB: learned, with the warning recorded
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "12345-5", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "APPROVED")
	Do $$$AssertTrue(tLog.ReviewNote [ "not in the LOINC KB", tLog.ReviewNote)
	Set tRow = ##class(AgenticProd.Data.LearnedMapping).%OpenId(##class(AgenticProd.Data.LearnedMapping).ActiveId("GLU-01"))
	Do $$$AssertEquals(tRow.Loinc, "12345-5")
	Do $$$AssertTrue(tRow.Warning [ "not in the LOINC KB", tRow.Warning)

	Do ..RemoveRevokeTasks(tRequest.HeaderId, tRouted.HeaderId)
	Do ##class(AgenticProd.Data.SavedCall).%DeleteId(tSaved.%Id())
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.SettingsAudit WHERE Scope = 'memory' AND Item = 'GLU-01'")
	Do ..RemoveTestMappings()
}

/// MAP_CODE stub on case pCase from a fake agent session whose search_loinc returned pSearched
/// ("" = no search_loinc call).
Method MapStub(pCase As %String, pCode As %String, pLoinc As %String, pSearched As %String, Output pRequest As AgenticProd.Msg.TriageRequest) As AgenticProd.Msg.Decision
{
	Do $$$AssertStatusOK(..Case(pCase, "UNMAPPED_CODE", .pRequest))
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.9, 0)
	Set tDecision.Mapping.LocalCode = pCode, tDecision.Mapping.Loinc = pLoinc
	Set tDecision.AgentSessionId = ..#TESTSESSION_$INCREMENT(^||AgenticProd.TestSession)
	Do:pSearched'="" $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("search_loinc", {"text":"stub"}, "OK", 1, 10, "", pRequest.HeaderId, tDecision.AgentSessionId, , , pSearched))
	Quit tDecision
}

/// Decide with the grounding gate on; returns Ground's result.
Method Grounded(pTriage As AgenticProd.Process.Triage, pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pFinal As AgenticProd.Msg.Decision, Output pOutcome As %String, Output pFixed As %Persistent) As %DynamicObject
{
	Do $$$AssertStatusOK(pTriage.Decide(pRequest, pDecision, 1, .pFinal, .pOutcome, .pFixed, .tGrounding))
	Quit tGrounding
}

/// Revoke review tasks for the two headers, once the Workflow operation has made them.
ClassMethod RemoveRevokeTasks(pHeader1 As %Integer, pHeader2 As %Integer)
{
	Set tSQL = "SELECT t.ID AS TaskId, r.ID AS RespId FROM AgenticProd_Msg.ApprovalTask t LEFT JOIN EnsLib_Workflow.TaskResponse r ON r.TaskStatus_Request = t.ID WHERE t.Reason %STARTSWITH 'mapping revoked' AND t.HeaderId IN (?, ?)"
	// The operation answers asynchronously; give it a few seconds to create the responses
	For i = 1:1:20 {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pHeader1, pHeader2), tOpen = 0
		While tRS.%Next() { Set:tRS.RespId="" tOpen = 1 }
		Quit:'tOpen
		Hang 0.5
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pHeader1, pHeader2)
	While tRS.%Next() {
		If tRS.RespId '= "" {
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM EnsLib_Workflow.Worklist WHERE Task = ?", tRS.RespId)
			Do ##class(EnsLib.Workflow.TaskResponse).%DeleteId(tRS.RespId)
		}
		Do ##class(AgenticProd.Msg.ApprovalTask).%DeleteId(tRS.TaskId)
	}
}

/// Learning loop end to end in the running production: approve 01, resend, and the message
/// reaches data/out through LabRouter with no Triage or agent message in the new session.
Method TestLearningLoop01()
{
	If '##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertSkipped("production not running")
		Quit
	}
	Do ..RemoveTestMappings()
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.9, 0)
	Set tDecision.Mapping.LocalCode = "GLU-01", tDecision.Mapping.Loinc = "2345-7"
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.Outcome, "APPROVED")
	// Only a queued request header can be resent; LoadCase leaves type and priority unset
	Set tHeader = ##class(Ens.MessageHeader).%OpenId(tResend)
	Set tHeader.Type = $$$eMessageTypeRequest, tHeader.Priority = $$$eMessagePriorityAsync, tHeader.TargetConfigName = "LabRouter"
	Do $$$AssertStatusOK(tHeader.%Save())

	Set tOutDir = "/home/irisowner/dev/data/out/"
	Set tBefore = ..OutFiles(tOutDir, "MSG00001_*")
	Set tFHIRBefore = ..OutFiles("/home/irisowner/dev/data/out-fhir/", "MSG00001_*")
	Set tTriage = ..Triage()
	Set tTriage.TargetConfigName = "LabRouter"
	If '$$$AssertStatusOK(tTriage.ResendOriginal(tResend, .tNewId)) Quit
	Set tSession = ##class(Ens.MessageHeader).%OpenId(tNewId).SessionId
	// LabRouter and NphiesOut run in their own jobs; a file within 15 s or the test fails
	For i = 1:1:30 {
		Set tNew = ""
		Set tAfter = ..OutFiles(tOutDir, "MSG00001_*")
		Set tPtr = 0
		While $LISTNEXT(tAfter, tPtr, tFile) {
			If '$LISTFIND(tBefore, tFile) Set tNew = tFile  Quit
		}
		Quit:tNew'=""
		Hang 0.5
	}
	If $$$AssertNotEquals(tNew, "", "resent message reached data/out") {
		Do ##class(%File).Delete(tNew)
	}
	// FHIR output runs after the HL7 send, in the same LabRouter call; a cold validator takes ~35 s
	Set tFHIRDir = "/home/irisowner/dev/data/out-fhir/", tNew = ""
	For i = 1:1:90 {
		Set tAfter = ..OutFiles(tFHIRDir, "MSG00001_*")
		Set tPtr = 0
		While $LISTNEXT(tAfter, tPtr, tFile) {
			If '$LISTFIND(tFHIRBefore, tFile) Set tNew = tFile  Quit
		}
		Quit:tNew'=""
		Hang 0.5
	}
	If $$$AssertNotEquals(tNew, "", "resent message reached data/out-fhir") {
		Set tStream = ##class(%Stream.FileCharacter).%New()
		Do tStream.LinkToFile(tNew)
		Set tBundle = ##class(%DynamicObject).%FromJSON(tStream)
		Set tObs = ##class(AgenticProd.Test.Operation.NphiesFHIROutTest).First(tBundle, "Observation")
		Do $$$AssertEquals($SELECT($IsObject(tObs): tObs.code.coding.%Get(0).code, 1: ""), "2345-7", "GLU-01 Observation carries the approved LOINC")
		Kill tStream
		Do ##class(%File).Delete(tNew)
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName IN ('Triage', 'TriageAgent')", tSession)
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.N, 0, "no Triage or agent message in session "_tSession)
	Do ..RemoveTestMappings()
}

/// ESCALATE with a fix: an approved fix is re-checked; PASS_NEEDS_REVIEW is enough once a person
/// approved it, FAIL and REFUSED are not.
Method TestReviewEscalateFix()
{
	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("AUTO_FIX", "BAD_FORMAT", 0.6, 1, "OBX(1):14", "2026-10-23 10:15", "202610231015")
	Do $$$AssertStatusOK(..Triage().Plan(tRequest, tDecision, .tFinal, .tOutcome))
	Do $$$AssertEquals(tOutcome, "DOWNGRADED:AUTO_FIX")
	Set tLog = ..Reviewed(tRequest, tFinal, "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_APPLIED", tLog.ReviewNote)
	If $$$AssertTrue($IsObject(tFixed), "new message built") {
		Do $$$AssertEquals(tFixed.GetValueAt("4:14"), "202610231015")
		Do $$$AssertEquals(tLog.FixedBodyId, tFixed.%Id(), "loop guard sees the reviewed fix")
		Do ##class(EnsLib.HL7.Message).%DeleteId(tFixed.%Id())
	}

	// Unit added by a person: not auto-fixable, but approved
	Do $$$AssertStatusOK(..Case("07", "MISSING_FIELD", .tRequest))
	Set tDecision = ..Stub("ESCALATE", "MISSING_FIELD", 0.7, 0, "OBX(1):6", "", "mmol/L")
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_APPLIED", tLog.ReviewNote)
	Do:$IsObject(tFixed) ##class(EnsLib.HL7.Message).%DeleteId(tFixed.%Id())

	Do $$$AssertStatusOK(..Case("05", "BAD_FORMAT", .tRequest))
	Set tDecision = ..Stub("ESCALATE", "BAD_FORMAT", 0.6, 0, "OBX(1):14", "2026-10-23 10:15", "2026/10/23 10:15")
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_FIX_FAILED")
	Do $$$AssertTrue(tLog.ReviewNote [ "did not pass", tLog.ReviewNote)
	Do $$$AssertEquals(tFixed, "")

	Do $$$AssertStatusOK(..Case("11", "IDENTITY_ISSUE", .tRequest))
	Set tDecision = ..Stub("ESCALATE", "IDENTITY_ISSUE", 0.9, 0, "PID(1):3.4", "", "SIMHOSP")
	Set tLog = ..Reviewed(tRequest, tDecision, "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_FIX_FAILED")
	Do $$$AssertTrue(tLog.ReviewNote [ "protected identity field", tLog.ReviewNote)
	Do $$$AssertEquals(tFixed, "")
}

Method TestReviewEscalateNoFix()
{
	Do $$$AssertStatusOK(..Case("17", "UNMAPPED_CODE", .tRequest))
	Set tLog = ..Reviewed(tRequest, ..Stub("ESCALATE", "UNMAPPED_CODE", 0.4, 0), "Approve", "", .tFixed)
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_CLOSED")
	Do $$$AssertEquals(tLog.Reviewer, "reviewer")
	Do $$$AssertEquals(tFixed, "")
}

/// Eval.Runner closing its own task: the scored outcome stays, nothing is mapped or resent.
Method TestReviewEvalCloseKeepsOutcome()
{
	Do $$$AssertStatusOK(..Case("01", "UNMAPPED_CODE", .tRequest))
	Set tRequest.ControlId = "EV999905-01"
	Set tDecision = ..Stub("MAP_CODE", "UNMAPPED_CODE", 0.8, 0)
	Set tLog = ..Reviewed(tRequest, tDecision, ##class(AgenticProd.Process.Triage).#EVALACTION, "2345-7", .tFixed, .tResend)
	Do $$$AssertEquals(tLog.EvalRunId, 999905, "row is an eval row")
	Do $$$AssertEquals(tLog.Outcome, "SENT_FOR_APPROVAL", "outcome as scored")
	Do $$$AssertEquals(tLog.Reviewer, "eval")
	Do $$$AssertTrue(tLog.ReviewedAt '= "", "no longer waiting")
	Do $$$AssertEquals(tResend, "", "nothing resent")
	Do $$$AssertEquals(..Mapped("GLU-01"), "", "nothing mapped")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE EvalRunId = 999905")
}

/// A saved session whose ContextData holds the empty first snapshot in front of the real one
/// (seen on build 154) still gives its messages; unreadable data gives "", never an error.
Method TestSessionContextConcatenated()
{
	Set tStream = ##class(%Stream.TmpCharacter).%New()
	Do tStream.Write("{""version"":1,""messages"":[],""stats"":{}}{""version"":1,""messages"":[{""role"":""tool"",""content"":""x""}],""stats"":{}}")
	Set tContext = ##class(AgenticProd.Process.Triage).SessionContext(tStream)
	Do $$$AssertTrue($IsObject(tContext), "parsed")
	Do $$$AssertEquals($SELECT($IsObject(tContext): tContext.messages.%Size(), 1: -1), 1, "last snapshot")
	Do tStream.Clear(), tStream.Write("not json")
	Do $$$AssertEquals(##class(AgenticProd.Process.Triage).SessionContext(tStream), "")
}

/// The eval action on a live row is not a pass to skip review: it counts as a reject.
Method TestReviewEvalActionOnLiveRowRejects()
{
	Do $$$AssertStatusOK(..Case("17", "UNMAPPED_CODE", .tRequest))
	Set tLog = ..Reviewed(tRequest, ..Stub("ESCALATE", "UNMAPPED_CODE", 0.4, 0), ##class(AgenticProd.Process.Triage).#EVALACTION, "", .tFixed)
	Do $$$AssertEquals(tLog.EvalRunId, "")
	Do $$$AssertEquals(tLog.Outcome, "REVIEW_REJECTED")
}

/// Log pDecision, then run Triage.Review with a stub Workflow answer from "reviewer".
/// Returns the reopened DecisionLog row.
Method Reviewed(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pAction As %String, pLoinc As %String, Output pFixed As %Persistent, Output pResend As %String, pNote As %String = "") As AgenticProd.Data.DecisionLog
{
	Do $$$AssertStatusOK(##class(AgenticProd.Data.DecisionLog).Record(pRequest, pDecision, .tLogId, "SENT_FOR_APPROVAL"))
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).FromDecision(pRequest, pDecision)
	Set tAnswer = ##class(EnsLib.Workflow.TaskResponse).%New()
	Set tAnswer.%Action = pAction, tAnswer.%UserName = "reviewer"
	Do tAnswer.%FormValues.SetAt(pLoinc, "Loinc")
	Do:pNote'="" tAnswer.%FormValues.SetAt(pNote, "Note")
	Do $$$AssertStatusOK(..Triage().Review(pRequest, tTask, tAnswer, tLogId, .pFixed, .pResend))
	Quit ##class(AgenticProd.Data.DecisionLog).%OpenId(tLogId)
}

/// LabCodeMap value for pCode, "" if unmapped.
ClassMethod Mapped(pCode As %String) As %String
{
	Quit ##class(Ens.Util.FunctionSet).Lookup("LabCodeMap", pCode)
}

/// GLU-01 is unmapped by design (eval case 01), so any entry for it is a test's.
ClassMethod RemoveTestMappings()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.LookupTable WHERE TableName = 'LabCodeMap' AND KeyName = 'GLU-01'")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.LearnedMapping WHERE LocalCode = 'GLU-01'")
}

/// $LIST of full paths in pDir matching pSpec.
ClassMethod OutFiles(pDir As %String, pSpec As %String) As %List
{
	Set tList = ""
	Set tFile = $ZSEARCH(pDir_pSpec)
	While tFile '= "" {
		Set tList = tList_$LISTBUILD(tFile)
		Set tFile = $ZSEARCH("")
	}
	Quit tList
}

Method AssertDowngraded(pFinal As AgenticProd.Msg.Decision, pOutcome As %String, pFrom As %String, pWhy As %String)
{
	Do $$$AssertEquals(pOutcome, "DOWNGRADED:"_pFrom)
	Do $$$AssertEquals(pFinal.Decision, "ESCALATE")
	Do $$$AssertNotTrue(pFinal.Validated)
	Do $$$AssertTrue(pFinal.Reason [ ("downgraded from "_pFrom_": "), pFinal.Reason)
	Do $$$AssertTrue(pFinal.Reason [ pWhy, pFinal.Reason)
}

Method Triage() As AgenticProd.Process.Triage
{
	// Ens.Host.%OnNew needs a config name, even outside a production
	Quit ##class(AgenticProd.Process.Triage).%New("TestTriage")
}

/// Load eval case pCaseId (see HL7Test.LoadCase) and build its TriageRequest.
Method Case(pCaseId As %String, pErrorClass As %String, Output pRequest As AgenticProd.Msg.TriageRequest) As %Status
{
	Set tSC = ##class(AgenticProd.Test.Tools.HL7Test).LoadCase(pCaseId, .tHeaderId, .tExpected)
	Quit:$$$ISERR(tSC) tSC
	Set pRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
	Set pRequest.HeaderId = tHeaderId
	Set pRequest.SessionId = tHeaderId
	Set pRequest.Source = ..#TESTSOURCE
	Set pRequest.Format = "HL7v2"
	Set pRequest.ErrorText = tExpected."error_text"
	Set pRequest.ErrorClass = pErrorClass
	Quit $$$OK
}

/// Stub agent decision with at most one fix step.
ClassMethod Stub(pDecision As %String, pErrorClass As %String, pConfidence As %Numeric, pValidated As %Boolean, pPath As %String = "", pFrom As %String = "", pTo As %String = "") As AgenticProd.Msg.Decision
{
	Set tDecision = ##class(AgenticProd.Msg.Decision).%New()
	Set tDecision.Decision = pDecision
	Set tDecision.ErrorClass = pErrorClass
	Set tDecision.Confidence = pConfidence
	Set tDecision.Validated = pValidated
	Set tDecision.Reason = "stub"
	Do:pPath'="" ..AddStep(tDecision, pPath, pFrom, pTo)
	Quit tDecision
}

ClassMethod AddStep(pDecision As AgenticProd.Msg.Decision, pPath As %String, pFrom As %String, pTo As %String)
{
	Set tStep = ##class(AgenticProd.Msg.FixStep).%New()
	Set tStep.Path = pPath, tStep.FromValue = pFrom, tStep.ToValue = pTo
	Do pDecision.Fix.Insert(tStep)
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveTestMappings()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE Source = ?", ..#TESTSOURCE)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.ToolCall WHERE AgentSessionId %STARTSWITH ?", ..#TESTSESSION)
	// Plan's downgrade warnings, logged outside a production
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SourceClass = 'AgenticProd.Process.Triage' AND (ConfigName IS NULL OR ConfigName = 'TestTriage')")
	Quit ##class(AgenticProd.Test.Tools.HL7Test).Cleanup()
}

}
