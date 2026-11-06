/// Recordings.Export and Load on a scratch run: nothing from the user's own runs is read or changed.
Class AgenticProd.Test.RecordingsTest Extends AgenticProd.Test.Case
{

Parameter LABEL = "T-REC-SCRATCH";

Parameter MODEL = "rec-scratch-model";

Method TestExportThenLoadRoundTripIsIdempotent()
{
	Do ..Clean()
	Do ..AddScratchRun()
	Set tFile = ##class(%File).TempFilename("json")
	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Export(..#LABEL, tFile))
	Do $$$AssertTrue(##class(%File).Exists(tFile), "file written")
	// Only the live row with a decision is exported, not the replay row
	Do ..Clean()
	Do $$$AssertEquals(..Count("EvalRun"), 0, "scratch run removed before the load")

	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Load(tFile))
	Do $$$AssertEquals(..Count("EvalRun"), 1, "run loaded")
	Do $$$AssertEquals(..Count("EvalResult"), 2, "results loaded")
	Do $$$AssertEquals(..Count("Usage"), 2, "usage loaded, replay row not exported")

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, FinalAccuracy, CaseCount, StartedAt FROM AgenticProd_Data.EvalRun WHERE Label = ?", ..#LABEL)
	Do tRS.%Next()
	Set tRunId = tRS.ID
	Do $$$AssertEquals(+tRS.FinalAccuracy, .9333, "headline number kept")
	Do $$$AssertEquals(tRS.CaseCount, 60)
	Do $$$AssertEquals(tRS.StartedAt, "2000-01-01 00:00:00", "start time kept: it is the idempotence key")

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 DecisionJSON, PromptHash, AgentSessionId, EvalRunId, Replay, CaseId FROM AgenticProd_Data.Usage WHERE Model = ? ORDER BY CaseId", ..#MODEL)
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.CaseId, "T97")
	Do $$$AssertEquals({}.%FromJSON(tRS.DecisionJSON).reason, "recorded T97", "decision kept")
	Do $$$AssertEquals(tRS.PromptHash, "00000000000000aa")
	Do $$$AssertEquals(tRS.AgentSessionId, "", "saved sessions are not shipped")
	Do $$$AssertEquals(tRS.EvalRunId, tRunId, "usage linked to the new run id")
	Do $$$AssertEquals(+tRS.Replay, 0, "loaded rows are live recordings")

	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Load(tFile))
	Do $$$AssertEquals(..Count("EvalRun"), 1, "second load adds no run")
	Do $$$AssertEquals(..Count("EvalResult"), 2, "second load adds no results")
	Do $$$AssertEquals(..Count("Usage"), 2, "second load adds no usage")

	Do ##class(%File).Delete(tFile)
}

/// Same label, other start time: it is a different run (the user's own), so the shipped one is
/// added beside it and the user's rows stay as they were.
Method TestLoadKeepsAnotherRunWithTheSameLabel()
{
	Do ..Clean()
	Do ..AddScratchRun()
	Set tFile = ##class(%File).TempFilename("json")
	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Export(..#LABEL, tFile))
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "UPDATE AgenticProd_Data.EvalRun SET StartedAt = '2001-02-03 04:05:06', Note = 'mine' WHERE Label = ?", ..#LABEL)
	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Load(tFile))
	Do $$$AssertEquals(..Count("EvalRun"), 2, "shipped run added")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.EvalRun WHERE Label = ? AND Note = 'mine'", ..#LABEL)
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.N, 1, "own run untouched")
	Do ##class(%File).Delete(tFile)
}

Method TestLoadWithoutFileDoesNothing()
{
	Do ..Clean()
	Do $$$AssertStatusOK(##class(AgenticProd.Recordings).Load("/nonexistent/recordings.json"))
	Do $$$AssertEquals(..Count("EvalRun"), 0)
}

Method TestExportNeedsAFinishedLiveRun()
{
	Do ..Clean()
	Set tFile = ##class(%File).TempFilename("json")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Recordings).Export(..#LABEL, tFile), "no such run")
	Do ##class(%File).Delete(tFile)
}

/// One finished live run with two results, two live recordings and one replay row.
Method AddScratchRun()
{
	Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
	Set tRun.Label = ..#LABEL, tRun.Model = ..#MODEL, tRun.Mode = "live", tRun.Status = "DONE"
	Set tRun.StartedAt = "2000-01-01 00:00:00", tRun.FinishedAt = "2000-01-01 00:10:00"
	Set tRun.CaseCount = 60, tRun.FinalAccuracy = .9333, tRun.TotalCostUsd = .12
	Do $$$AssertStatusOK(tRun.%Save())
	Set tRunId = tRun.%Id()
	For tCase = "T97", "T98" {
		Set tRes = ##class(AgenticProd.Data.EvalResult).%New()
		Set tRes.RunId = tRunId, tRes.CaseId = tCase, tRes.ExpectedDecision = "ESCALATE", tRes.AgentDecision = "ESCALATE"
		Do $$$AssertStatusOK(tRes.%Save())
		Set tUse = ##class(AgenticProd.Data.Usage).%New()
		Set tUse.Model = ..#MODEL, tUse.EvalRunId = tRunId, tUse.CaseId = tCase
		Set tUse.PromptTokens = 100, tUse.CompletionTokens = 20, tUse.CostUsd = .001
		Set tUse.Decision = "ESCALATE", tUse.PromptHash = "00000000000000aa"
		Set tUse.AgentSessionId = "991"
		Set tUse.DecisionJSON = {"decision":"ESCALATE","error_class":"OTHER","confidence":0.5,"reason":("recorded "_tCase)}.%ToJSON()
		Do $$$AssertStatusOK(tUse.%Save())
	}
	Set tUse = ##class(AgenticProd.Data.Usage).%New()
	Set tUse.Model = ..#MODEL, tUse.EvalRunId = tRunId, tUse.CaseId = "T97", tUse.Replay = 1
	Set tUse.DecisionJSON = {"decision":"ESCALATE","reason":"replay row"}.%ToJSON()
	Do $$$AssertStatusOK(tUse.%Save())
}

/// Scratch rows in the three tables: 0 means the table has none of this test's rows.
Method Count(pTable As %String) As %Integer
{
	Set tSql = $CASE(pTable,
		"EvalRun": "SELECT COUNT(*) AS N FROM AgenticProd_Data.EvalRun WHERE Label = '"_..#LABEL_"'",
		"EvalResult": "SELECT COUNT(*) AS N FROM AgenticProd_Data.EvalResult WHERE RunId IN (SELECT ID FROM AgenticProd_Data.EvalRun WHERE Label = '"_..#LABEL_"')",
		: "SELECT COUNT(*) AS N FROM AgenticProd_Data.Usage WHERE Model = '"_..#MODEL_"'")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSql)
	Do tRS.%Next()
	Quit tRS.N
}

Method Clean()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.EvalResult WHERE RunId IN (SELECT ID FROM AgenticProd_Data.EvalRun WHERE Label = '"_..#LABEL_"')")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.Usage WHERE Model = '"_..#MODEL_"'")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.EvalRun WHERE Label = '"_..#LABEL_"'")
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

}
