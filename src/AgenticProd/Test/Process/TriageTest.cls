Include Ensemble

/// Process.Triage action matrix with stub decisions on eval cases. Calls Plan, Review and
/// ApplyMapping directly, no LLM. Only TestLearningLoop01 sends, into the running production.
Class AgenticProd.Test.Process.TriageTest Extends %UnitTest.TestCase
{

/// Request Source of the DecisionLog rows these tests write, so cleanup finds them.
Parameter TESTSOURCE = "AgenticProd.Test.Process";

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
	Do $$$AssertEquals(tTask.%FormFields, "Loinc")
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
	For tCode = "2345-7", "2339-0", "2093-3", "17861-6", "630-4" {
		Do $$$AssertEquals(##class(AgenticProd.Process.Triage).LoincProblem(tCode), "", tCode_" valid")
	}
	For tCode = "2345-8", "2345", "2345-77", "123456-1", "GLU-01", "" {
		Do $$$AssertNotEquals(##class(AgenticProd.Process.Triage).LoincProblem(tCode), "", "'"_tCode_"' refused")
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

/// Log pDecision, then run Triage.Review with a stub Workflow answer from "reviewer".
/// Returns the reopened DecisionLog row.
Method Reviewed(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pAction As %String, pLoinc As %String, Output pFixed As %Persistent, Output pResend As %String) As AgenticProd.Data.DecisionLog
{
	Do $$$AssertStatusOK(##class(AgenticProd.Data.DecisionLog).Record(pRequest, pDecision, .tLogId, "SENT_FOR_APPROVAL"))
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).FromDecision(pRequest, pDecision)
	Set tAnswer = ##class(EnsLib.Workflow.TaskResponse).%New()
	Set tAnswer.%Action = pAction, tAnswer.%UserName = "reviewer"
	Do tAnswer.%FormValues.SetAt(pLoinc, "Loinc")
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
	// Plan's downgrade warnings, logged outside a production
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SourceClass = 'AgenticProd.Process.Triage' AND (ConfigName IS NULL OR ConfigName = 'TestTriage')")
	Quit ##class(AgenticProd.Test.Tools.HL7Test).Cleanup()
}

}
