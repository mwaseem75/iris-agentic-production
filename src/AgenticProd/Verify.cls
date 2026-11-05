/// Install check for the README ("Verify it works"). Prints PASS, FAIL or SKIP per step and returns
/// an error status when a step fails. Never calls an LLM and changes nothing the user owns: the
/// replay steps run the agent operation in this process and delete only their own Usage rows.
Class AgenticProd.Verify
{

/// Header ID and eval run ID of the replay checks. Rows with these values are the checks' own.
Parameter HEADERID = -7001;

Parameter EVALRUN = 8000001;

/// Case checked on its own, then three cases scored against what was recorded.
Parameter SAMPLECASE = "05";

Parameter SCORECASES = "05,08,11";

/// pStrict = 1 counts a skipped step (no recorded run to replay) as a failure.
ClassMethod Run(pStrict As %Boolean = 0) As %Status
{
	Set tFail = 0, tSkip = 0, tTotal = 0
	Write "AgenticProd verify, no LLM call", !
	For tStep = "HL7", "Production", "AIHub", "LoincKB", "SampleCase", "ReplayScores" {
		Set tTotal = tTotal + 1, tWhy = ""
		Set tResult = $CLASSMETHOD($CLASSNAME(), "Check"_tStep, .tWhy)
		Write $CASE(tResult, 1: "PASS", 0: "FAIL", : "SKIP"), "  ", tWhy, !
		Set:(tResult = 0) tFail = tFail + 1
		Set:(tResult = -1) tSkip = tSkip + 1
	}
	Set:(pStrict && tSkip) tFail = tFail + tSkip
	Write $SELECT(tFail: "Verify FAILED: "_tFail_" of "_tTotal_" steps", 1: "Verify PASSED: "_(tTotal - tSkip)_" of "_tTotal_" steps"_$SELECT(tSkip: ", "_tSkip_" skipped", 1: "")), !
	Quit $SELECT(tFail: $$$ERROR($$$GeneralError, "verify failed"), 1: $$$OK)
}

ClassMethod CheckHL7(Output pWhy As %String) As %Integer
{
	Set tOk = ##class(%Dictionary.CompiledClass).%ExistsId("EnsLib.HL7.Message")
	Set pWhy = "HL7 classes: EnsLib.HL7.Message "_$SELECT(tOk: "found", 1: "missing, this needs IRIS for Health")
	Quit tOk
}

ClassMethod CheckProduction(Output pWhy As %String) As %Integer
{
	Set tSC = ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	// 1 = running
	Set tOk = $$$ISOK(tSC) && (tState = 1)
	Set pWhy = "Production: "_tName_" "_$CASE(tState, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", : "state "_tState)
	Quit tOk
}

ClassMethod CheckAIHub(Output pWhy As %String) As %Integer
{
	Set tOk = ##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent")
	Set pWhy = "AI Hub: %AI.Agent "_$SELECT(tOk: "found on IRIS "_$SYSTEM.Version.GetNumber(), 1: "missing, this needs the AI Hub image")
	Quit tOk
}

ClassMethod CheckLoincKB(Output pWhy As %String) As %Integer
{
	Set tRows = 0
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM "_##class(AgenticProd.Tools.Mapping).#LOINCTABLE)
		Set:tRS.%Next() tRows = +tRS.N
	} Catch {}
	Set pWhy = "LOINC knowledge base: "_tRows_" rows"
	Quit (tRows > 0)
}

/// Case SAMPLECASE through the agent operation in replay mode: the recorded decision must be one the
/// case accepts, and AUTO_FIX is the expected one.
ClassMethod CheckSampleCase(Output pWhy As %String) As %Integer
{
	Set tCase = ..#SAMPLECASE
	Set tSC = ..Replay(tCase, .tDecision, .tExpected, .tModel)
	If tSC = -1 {
		Set pWhy = "Sample case "_tCase_": no recorded live run to replay; run the eval once with a key, or see the README"
		Quit -1
	}
	If $$$ISERR(tSC) {
		Set pWhy = "Sample case "_tCase_": "_$SYSTEM.Status.GetErrorText(tSC)
		Quit 0
	}
	Set tScore = ##class(AgenticProd.Eval.Runner).Score(tExpected, tDecision, "")
	Set pWhy = "Sample case "_tCase_" replayed from "_tModel_": decision "_tDecision.decision_", expected "_tExpected.decision
		_$SELECT(tScore.Acceptable: "", 1: " (not accepted by the case)")
	Quit ''tScore.Acceptable
}

/// Re-scores SCORECASES from their replayed decisions and compares Acceptable, Exact and UnsafeAgent
/// with the latest live eval result recorded for the same case and model (or, with no eval run, with
/// the recorded decision scored the same way).
ClassMethod CheckReplayScores(Output pWhy As %String) As %Integer
{
	Set tChecked = 0, tBad = "", tSkipped = 0
	For i = 1:1:$LENGTH(..#SCORECASES, ",") {
		Set tCase = $PIECE(..#SCORECASES, ",", i)
		Set tSC = ..Replay(tCase, .tDecision, .tExpected, .tModel)
		If tSC = -1 {
			Set tSkipped = tSkipped + 1
			Continue
		}
		If $$$ISERR(tSC) {
			Set tBad = tBad_$SELECT(tBad '= "": "; ", 1: "")_tCase_": "_$SYSTEM.Status.GetErrorText(tSC)
			Continue
		}
		Set tScore = ##class(AgenticProd.Eval.Runner).Score(tExpected, tDecision, "")
		Set tRec = ..RecordedScore(tCase, tModel)
		If '$IsObject(tRec) {
			Set tBad = tBad_$SELECT(tBad '= "": "; ", 1: "")_tCase_": no recorded score"
			Continue
		}
		Set tChecked = tChecked + 1
		If (+tScore.Acceptable '= +tRec.Acceptable) || (+tScore.Exact '= +tRec.Exact) || (+tScore.UnsafeAgent '= +tRec.UnsafeAgent) {
			Set tBad = tBad_$SELECT(tBad '= "": "; ", 1: "")_tCase_": replay scores "_+tScore.Acceptable_"/"_+tScore.Exact_"/"_+tScore.UnsafeAgent_", recorded "_+tRec.Acceptable_"/"_+tRec.Exact_"/"_+tRec.UnsafeAgent
		}
	}
	If (tSkipped = $LENGTH(..#SCORECASES, ",")) && (tBad = "") {
		Set pWhy = "Replay scores: no recorded live runs to replay"
		Quit -1
	}
	Set pWhy = "Replay scores: "_tChecked_" of "_$LENGTH(..#SCORECASES, ",")_" cases match the recorded run"_$SELECT(tBad '= "": " ("_tBad_")", 1: "")
	Quit (tBad = "")
}

/// -1 when no live run of pCase is recorded. Otherwise the decision replayed for pCase as an object,
/// the case's expected.json and the model the recording is for. The replay writes one Usage row of its
/// own (HEADERID, EVALRUN); it is deleted before returning.
ClassMethod Replay(pCase As %String, Output pDecision As %DynamicObject, Output pExpected As %DynamicObject, Output pModel As %String) As %Status
{
	Set (pDecision, pExpected, pModel) = ""
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(AgenticProd.Eval.Runner).LoadCases(pCase, .tCases, .tCount))
		Set pExpected = tCases("c"_pCase)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Model FROM AgenticProd_Data.Usage WHERE CaseId = ? AND COALESCE(Replay, 0) = 0 AND DecisionJSON IS NOT NULL AND (EvalRunId IS NULL OR EvalRunId <> ?) ORDER BY ID DESC", pCase, ..#EVALRUN)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		If 'tRS.%Next() Quit
		Set pModel = tRS.Model
		Set tOp = ##class(AgenticProd.Operation.Agent).%New("AgenticProdVerify")
		Set tOp.Mode = "replay", tOp.Model = pModel
		Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
		Set tRequest.HeaderId = ..#HEADERID, tRequest.ControlId = "EV"_..#EVALRUN_"-"_pCase
		Set tRequest.Source = pExpected.source, tRequest.Format = pExpected.format
		Set tRequest.ErrorClass = pExpected."error_class", tRequest.ErrorText = pExpected."error_text"
		$$$ThrowOnError(tOp.Triage(tRequest, .tResponse))
		$$$ThrowOnError(tResponse.%JSONExportToString(.tJSON))
		Set pDecision = {}.%FromJSON(tJSON)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Do ..DeleteOwnRows()
	Quit $SELECT($$$ISERR(tSC): tSC, pModel = "": -1, 1: $$$OK)
}

/// Acceptable, Exact and UnsafeAgent of the latest live eval result for pCase and pModel.
ClassMethod RecordedScore(pCase As %String, pModel As %String) As %DynamicObject
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 r.Acceptable, r.Exact, r.UnsafeAgent FROM AgenticProd_Data.EvalResult r JOIN AgenticProd_Data.EvalRun e ON e.ID = r.RunId WHERE r.CaseId = ? AND e.Model = ? AND e.Mode = 'live' ORDER BY r.ID DESC", pCase, pModel)
	Quit:'tRS.%Next() ""
	Quit {"Acceptable":(+tRS.Acceptable), "Exact":(+tRS.Exact), "UnsafeAgent":(+tRS.UnsafeAgent)}
}

ClassMethod DeleteOwnRows() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND EvalRunId = ?", ..#HEADERID, ..#EVALRUN)
}

}
