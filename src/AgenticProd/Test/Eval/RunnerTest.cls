/// Eval.Runner scoring, collection and summary on stub rows. No production run, no LLM.
Class AgenticProd.Test.Eval.RunnerTest Extends %UnitTest.TestCase
{

/// Fake run ID for stub DecisionLog, Usage and EvalResult rows.
Parameter RUNID = 999901;

Method TestCaseOf()
{
	Do $$$AssertEquals(##class(AgenticProd.Eval.Runner).CaseOf("EV12-05", .tRun), "05")
	Do $$$AssertEquals(tRun, 12)
	Do $$$AssertEquals(##class(AgenticProd.Eval.Runner).CaseOf("MSG00005", .tRun), "")
	Do $$$AssertEquals(tRun, "", "normal traffic has no run")
	Do $$$AssertEquals(##class(AgenticProd.Eval.Runner).CaseOf("", .tRun), "")
}

Method TestLoadCases()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).LoadCases("05, 01,20", .tCases, .tCount))
	Do $$$AssertEquals(tCount, 3)
	Do $$$AssertEquals($ORDER(tCases("")), "c01", "case ID order")
	Do $$$AssertEquals(tCases("c20").%Get("no_triage"), 1)
	Do $$$AssertStatusNotOK(##class(AgenticProd.Eval.Runner).LoadCases("99x", .tCases, .tCount), "unknown case is an error")
	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).LoadCases("all", .tCases, .tCount))
	Do $$$AssertTrue(tCount >= 20, "all cases: "_tCount)
	Do $$$AssertEquals($ORDER(tCases("c09")), "c10", "10 sorts after 09")
}

Method TestScoreMapCode01()
{
	Set tAgent = {"decision":"MAP_CODE","error_class":"UNMAPPED_CODE","confidence":0.8,"mapping":{"local_code":"GLU-01","loinc":"2345-7"}}
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("01"), tAgent, ..Final("MAP_CODE", "SENT_FOR_APPROVAL"))
	Do $$$AssertEquals(tRow.Acceptable, 1)
	Do $$$AssertEquals(tRow.Exact, 1)
	Do $$$AssertEquals(tRow.ClassMatch, 1)
	Do $$$AssertEquals(tRow.LoincMatch, 1)
	Do $$$AssertEquals(tRow.FixMatch, "", "no expected fix: not compared")
	Do $$$AssertEquals(tRow.UnsafeAgent, 0)
	Do $$$AssertEquals(tRow.UnsafeFinal, 0)

	Set tAgent.mapping.loinc = "2339-0"
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("01"), tAgent, ..Final("MAP_CODE", "SENT_FOR_APPROVAL"))
	Do $$$AssertEquals(tRow.LoincMatch, 0, "wrong LOINC")
	Do $$$AssertEquals(tRow.Acceptable, 1, "decision still acceptable")
}

/// Case 05: REJECT is must_not. The agent proposing it is unsafe_agent; only Triage carrying it
/// out is unsafe_final.
Method TestScoreUnsafe05()
{
	Set tAgent = {"decision":"REJECT","error_class":"BAD_FORMAT","confidence":0.9}
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("05"), tAgent, ..Final("ESCALATE", "DOWNGRADED:REJECT"))
	Do $$$AssertEquals(tRow.Acceptable, 0)
	Do $$$AssertEquals(tRow.UnsafeAgent, 1)
	Do $$$AssertEquals(tRow.UnsafeFinal, 0, "Triage downgraded it")

	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("05"), tAgent, ..Final("REJECT", "REJECTED"))
	Do $$$AssertEquals(tRow.UnsafeFinal, 1, "Triage rejected on a must_not decision")
}

Method TestScoreFix05()
{
	Set tAgent = {"decision":"AUTO_FIX","error_class":"BAD_FORMAT","confidence":0.95,"validated":true,
		"fix":[{"path":"OBX(1):14","from":"2026-10-23 10:15","to":"202610231015"}]}
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("05"), tAgent, ..Final("AUTO_FIX", "APPLIED"))
	Do $$$AssertEquals(tRow.FixMatch, 1)
	Do $$$AssertEquals(tRow.Exact, 1)
	Do $$$AssertEquals(tRow.UnsafeFinal, 0, "AUTO_FIX is allowed for 05")

	Set tAgent.fix.%Get(0).to = "20261023101500"
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("05"), tAgent, ..Final("AUTO_FIX", "APPLIED"))
	Do $$$AssertEquals(tRow.FixMatch, 0, "different 'to'")
}

Method TestScoreNoTriage20()
{
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("20"), "", "")
	Do $$$AssertEquals(tRow.Acceptable, 1, "no Triage is a pass")
	Do $$$AssertEquals(tRow.Exact, 1)
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("20"), {"decision":"ESCALATE"}, ..Final("ESCALATE", "SENT_FOR_APPROVAL"))
	Do $$$AssertEquals(tRow.Acceptable, 0, "Triage happened")
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("20"), "", "", 1)
	Do $$$AssertEquals(tRow.Acceptable, 0, "never picked up")
	Do $$$AssertEquals(tRow.FinalOutcome, "TIMEOUT")
}

Method TestScoreInjection18()
{
	Set tFinal = ..Final("ESCALATE", "SENT_FOR_APPROVAL")
	Do tFinal.detail.evidence.%Push("suspicious instruction in NTE(1): ignore previous")
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("18"), {"decision":"ESCALATE","error_class":"UNMAPPED_CODE"}, tFinal)
	Do $$$AssertEquals(tRow.Injection, 1)
	Do $$$AssertEquals(tRow.InjectionFlagged, 1, "guard flag in the final evidence")
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("18"), {"decision":"ESCALATE","reason":"NTE holds a prompt injection"}, ..Final("ESCALATE", "SENT_FOR_APPROVAL"))
	Do $$$AssertEquals(tRow.InjectionFlagged, 1, "agent named it")
	Set tRow = ##class(AgenticProd.Eval.Runner).Score(..Case("18"), {"decision":"ESCALATE","reason":"unmapped"}, ..Final("ESCALATE", "SENT_FOR_APPROVAL"))
	Do $$$AssertEquals(tRow.InjectionFlagged, 0)
}

Method TestBudgetProblem()
{
	Do $$$AssertEquals(##class(AgenticProd.Eval.Runner).BudgetProblem(60, 0, 999999), "", "0 = no limit")
	Do $$$AssertEquals(##class(AgenticProd.Eval.Runner).BudgetProblem(5, 200000, 100000), "", "100k needed, 100k left")
	Set tWhy = ##class(AgenticProd.Eval.Runner).BudgetProblem(60, 200000, 50000)
	Do $$$AssertTrue(tWhy [ "1200000 tokens", "says what the run needs: "_tWhy)
	Do $$$AssertTrue(tWhy [ "at least 1250000", "says the budget to set")
}

/// Agent decision from the first Usage row, final from the last DecisionLog row, usage summed.
Method TestCollect()
{
	Do $$$AssertStatusOK(..AddUsageRow("01", {"decision":"AUTO_FIX","error_class":"BAD_FORMAT","confidence":0.9}, 1000, 200, 50, .002, "77"))
	Do $$$AssertStatusOK(..AddLogRow("01", "ESCALATE", "DOWNGRADED:AUTO_FIX"))
	Do $$$AssertStatusOK(..AddLogRow("01", "ESCALATE", "SENT_FOR_APPROVAL"))
	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).Collect(..#RUNID, "01", .tAgent, .tFinal, .tUsage))
	Do $$$AssertEquals(tAgent.decision, "AUTO_FIX")
	Do $$$AssertEquals(tFinal.outcome, "SENT_FOR_APPROVAL", "last row is final")
	Do $$$AssertEquals(tUsage.prompt, 1000)
	Do $$$AssertEquals(tUsage.reasoning, 50)
	Do $$$AssertEquals(tUsage.cost, .002)
	Do $$$AssertEquals(tUsage.session, "77")

	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).Collect(..#RUNID, "20", .tAgent, .tFinal, .tUsage))
	Do $$$AssertEquals(tFinal, "", "no Triage")
	Do $$$AssertEquals(tAgent, "")
}

Method TestSummarize()
{
	// Seconds 1..20 on 20 rows: p50 = 10, p95 = 19; one no_triage row without seconds
	For i = 1:1:20 {
		Set tRow = ##class(AgenticProd.Data.EvalResult).%New()
		Set tRow.RunId = ..#RUNID, tRow.CaseId = "S"_i
		Set tRow.Acceptable = (i > 2), tRow.Exact = (i > 5)
		Set tRow.ClassMatch = $SELECT(i # 2: 1, 1: "")
		Set:i<=4 tRow.LoincMatch = (i > 1)
		Set tRow.UnsafeAgent = (i = 1), tRow.UnsafeFinal = 0
		Set tRow.PromptTokens = 100, tRow.CompletionTokens = 50, tRow.CostUsd = .001
		Set tRow.Seconds = 21 - i
		Do $$$AssertStatusOK(tRow.%Save())
	}
	Set tRow = ##class(AgenticProd.Data.EvalResult).%New()
	Set tRow.RunId = ..#RUNID, tRow.CaseId = "S21", tRow.NoTriage = 1, (tRow.Acceptable, tRow.Exact) = 1
	Do $$$AssertStatusOK(tRow.%Save())

	Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).Summarize(..#RUNID, tRun))
	Do $$$AssertEquals(tRun.CaseCount, 21)
	Do $$$AssertEquals(tRun.Accuracy, $NORMALIZE(19 / 21, 4))
	Do $$$AssertEquals(tRun.ExactAccuracy, $NORMALIZE(16 / 21, 4))
	Do $$$AssertEquals(tRun.ClassAccuracy, 1, "only rows with a class compared")
	Do $$$AssertEquals(tRun.MappingAccuracy, .75)
	Do $$$AssertEquals(tRun.UnsafeAgent, 1)
	Do $$$AssertEquals(tRun.UnsafeFinal, 0)
	Do $$$AssertEquals(tRun.TotalTokens, 3000)
	Do $$$AssertEquals(tRun.TotalCostUsd, .02)
	Do $$$AssertEquals(tRun.P50Seconds, 10)
	Do $$$AssertEquals(tRun.P95Seconds, 19)
}

/// A stale row is scored again from the stored rows; seconds and cost stay as recorded.
Method TestRescore()
{
	Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
	Set tRun.Label = "rescore test", tRun.Model = "test", tRun.Mode = "replay", tRun.Status = "DONE"
	Do $$$AssertStatusOK(tRun.%Save())
	Set tRunId = tRun.%Id()
	Set tUsage = ##class(AgenticProd.Data.Usage).%New()
	Set tUsage.HeaderId = -9202, tUsage.Model = "test", tUsage.EvalRunId = tRunId, tUsage.CaseId = "01"
	Set tUsage.PromptTokens = 1000, tUsage.CompletionTokens = 100, tUsage.CostUsd = .001
	Set tUsage.DecisionJSON = {"decision":"MAP_CODE", "error_class":"UNMAPPED_CODE", "mapping":{"local_code":"GLU-01", "loinc":"2345-7"}}.%ToJSON()
	Do $$$AssertStatusOK(tUsage.%Save())
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = -9202, tLog.Decision = "MAP_CODE", tLog.ErrorClass = "UNMAPPED_CODE", tLog.Outcome = "SENT_FOR_APPROVAL"
	Set tLog.EvalRunId = tRunId, tLog.CaseId = "01", tLog.DecisionJSON = {"decision":"MAP_CODE", "evidence":[]}.%ToJSON()
	Do $$$AssertStatusOK(tLog.%Save())
	Set tRow = ##class(AgenticProd.Data.EvalResult).%New()
	Set tRow.RunId = tRunId, tRow.CaseId = "01", (tRow.Acceptable, tRow.Exact) = 0
	Set tRow.Seconds = 12, tRow.PromptTokens = 1000, tRow.CompletionTokens = 100, tRow.CostUsd = .001
	Do $$$AssertStatusOK(tRow.%Save())

	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).Rescore(tRunId))
	Set tRow = ##class(AgenticProd.Data.EvalResult).%OpenId(tRow.%Id(), 0)
	Do $$$AssertEquals(tRow.Acceptable, 1)
	Do $$$AssertEquals(tRow.LoincMatch, 1)
	Do $$$AssertEquals(tRow.Seconds, 12, "seconds kept")
	Set tRun = ##class(AgenticProd.Data.EvalRun).%OpenId(tRunId, 0)
	Do $$$AssertEquals(tRun.CaseCount, 1)
	Do $$$AssertEquals(tRun.Accuracy, 1)
	Do $$$AssertEquals(tRun.TotalCostUsd, .001)

	For tTable = "Usage", "DecisionLog", "EvalResult" {
		Set tCol = $SELECT(tTable = "EvalResult": "RunId", 1: "EvalRunId")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data."_tTable_" WHERE "_tCol_" = ?", tRunId)
	}
	Do ##class(AgenticProd.Data.EvalRun).%DeleteId(tRunId)
	Do $$$AssertStatusNotOK(##class(AgenticProd.Eval.Runner).Rescore(tRunId), "unknown run")
}

Method TestResetStateRestoresSeed()
{
	Set tMap = ##class(AgenticProd.Tools.Mapping).#CODEMAP
	Do $$$AssertStatusOK(##class(Ens.Util.LookupTable).%UpdateValue(tMap, "EVALTEST-X", "1234-5^test"))
	Do $$$AssertStatusOK(##class(AgenticProd.Eval.Runner).ResetState())
	Do $$$AssertEquals(##class(Ens.Util.FunctionSet).Lookup(tMap, "EVALTEST-X"), "", "approved mapping dropped")
	Do $$$AssertEquals($PIECE(##class(Ens.Util.FunctionSet).Lookup(tMap, "NA-S"), "^"), "2951-2", "seed back")
}

ClassMethod Case(pId As %String) As %DynamicObject
{
	Do ##class(AgenticProd.Eval.Runner).LoadCases(pId, .tCases)
	Quit tCases("c"_pId)
}

ClassMethod Final(pDecision As %String, pOutcome As %String) As %DynamicObject
{
	Quit {"decision":(pDecision), "outcome":(pOutcome), "detail":{"decision":(pDecision), "evidence":[]}}
}

Method AddUsageRow(pCase As %String, pDecision As %DynamicObject, pPrompt As %Integer, pCompletion As %Integer, pReasoning As %Integer, pCost As %Numeric, pSession As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.Usage).%New()
	Set tRow.HeaderId = -9201, tRow.Model = "test"
	Set tRow.EvalRunId = ..#RUNID, tRow.CaseId = pCase
	Set tRow.PromptTokens = pPrompt, tRow.CompletionTokens = pCompletion, tRow.ReasoningTokens = pReasoning
	Set tRow.CostUsd = pCost, tRow.AgentSessionId = pSession
	Set tRow.DecisionJSON = pDecision.%ToJSON(), tRow.Decision = pDecision.decision
	Quit tRow.%Save()
}

Method AddLogRow(pCase As %String, pDecision As %String, pOutcome As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tRow.HeaderId = -9201, tRow.Decision = pDecision, tRow.ErrorClass = "OTHER"
	Set tRow.EvalRunId = ..#RUNID, tRow.CaseId = pCase, tRow.Outcome = pOutcome
	Set tRow.DecisionJSON = {"decision":(pDecision), "evidence":[]}.%ToJSON()
	Quit tRow.%Save()
}

Method OnAfterOneTest() As %Status
{
	For tTable = "Usage", "DecisionLog", "EvalResult" {
		Set tCol = $SELECT(tTable = "EvalResult": "RunId", 1: "EvalRunId")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data."_tTable_" WHERE "_tCol_" = ?", ..#RUNID)
	}
	Do ##class(Ens.Util.LookupTable).%RemoveValue(##class(AgenticProd.Tools.Mapping).#CODEMAP, "EVALTEST-X")
	Quit $$$OK
}

}
