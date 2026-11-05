/// Verify steps that need no recording, and that the replay steps leave no rows behind. No LLM.
Class AgenticProd.Test.VerifyTest Extends AgenticProd.Test.Case
{

Method TestChecksThatNeedOnlyTheInstall()
{
	Do $$$AssertEquals(##class(AgenticProd.Verify).CheckHL7(.tWhy), 1, tWhy)
	Do $$$AssertEquals(##class(AgenticProd.Verify).CheckAIHub(.tWhy), 1, tWhy)
	Do $$$AssertEquals(##class(AgenticProd.Verify).CheckLoincKB(.tWhy), 1, tWhy)
}

/// A case with no recorded run is skipped, not failed; an unknown case is an error.
Method TestReplayWithoutRecordingAndUnknownCase()
{
	Set tSC = ##class(AgenticProd.Verify).Replay("99", .tDecision, .tExpected, .tModel)
	Do $$$AssertTrue($$$ISERR(tSC), "no case file for 99")
	Do $$$AssertEquals(##class(AgenticProd.Verify).RecordedScore("99", "no-model"), "", "no recorded score")
}

Method TestReplayLeavesNoRowsBehind()
{
	Set tBefore = ..Rows()
	Do ##class(AgenticProd.Verify).CheckSampleCase(.tWhy)
	Do ##class(AgenticProd.Verify).CheckReplayScores(.tWhy)
	Do $$$AssertEquals(..Rows(), tBefore, "the checks delete their own Usage rows")
}

ClassMethod Rows() As %Integer [ Private ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND EvalRunId = ?", ##class(AgenticProd.Verify).#HEADERID, ##class(AgenticProd.Verify).#EVALRUN)
	Do tRS.%Next()
	Quit tRS.N
}

}
