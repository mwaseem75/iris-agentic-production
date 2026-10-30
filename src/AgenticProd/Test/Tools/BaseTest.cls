/// Tools.Base on a saved eval case (05) and synthetic DecisionLog rows. No LLM.
Class AgenticProd.Test.Tools.BaseTest Extends AgenticProd.Test.Case
{

/// Local code used only by these tests, so other DecisionLog rows never match.
Parameter TESTCODE = "ZZTEST-01";

Method TestGetFailedMessageMasksPid()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Test.Tools.HL7Test).LoadCase("05", .tHeaderId))
	Set tOut = ##class(AgenticProd.Tools.Base).%New().GetFailedMessage(tHeaderId)
	Do $$$AssertTrue(tOut [ "<untrusted_data source=""failed_message""", "wrapped as untrusted")
	Do $$$AssertTrue(tOut [ "PID|1||100001^^^SIMHOSP^MR||***||***|M", "PID-5 and PID-7 masked")
	Do $$$AssertTrue(tOut [ "OBX|1|NM|NA-S", "rest of the message shown")
	Do $$$AssertTrue(##class(AgenticProd.Tools.Base).%New().GetFailedMessage(-1) [ "No message header")
}

Method TestGetErrorEventsReadsSessionLog()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Test.Tools.HL7Test).LoadCase("05", .tHeaderId))
	For tType = 2, 4 {
		Set tLog = ##class(Ens.Util.Log).%New()
		Set tLog.SessionId = tHeaderId
		Set tLog.ConfigName = ##class(AgenticProd.Test.Tools.HL7Test).#TESTSOURCE
		Set tLog.Type = tType
		Set tLog.Text = $SELECT(tType = 2: "OBX(1):14 '2026-10-23 10:15' is not a valid TS", 1: "info only")
		Set tLog.TimeLogged = $ZDATETIME($ZTIMESTAMP, 3)
		Do $$$AssertStatusOK(tLog.%Save())
	}
	Set tOut = ##class(AgenticProd.Tools.Base).%New().GetErrorEvents(tHeaderId)
	Do $$$AssertTrue(tOut [ "<untrusted_data source=""error_events""")
	Do $$$AssertTrue(tOut [ "is not a valid TS", "error event returned")
	Do $$$AssertNotTrue(tOut [ "info only", "info events left out")
}

Method TestGetSimilarDecisions()
{
	For i = 1:1:7 {
		Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
		Set tRow.HeaderId = -9200 - i
		Set tRow.Decision = "MAP_CODE"
		Set tRow.ErrorClass = "UNMAPPED_CODE"
		Set tRow.LocalCode = ..#TESTCODE
		Set tRow.Loinc = "2345-7"
		Set tRow.Reason = "test row "_i
		Set tRow.DecisionJSON = "{""fix"":[]}"
		Do $$$AssertStatusOK(tRow.%Save())
	}
	Set tOut = ##class(AgenticProd.Tools.Base).%New().GetSimilarDecisions("unmapped_code", ..#TESTCODE)
	Set tList = [].%FromJSON($PIECE(tOut, $CHAR(10), 2))
	Do $$$AssertEquals(tList.%Size(), 5, "last 5 only: "_$EXTRACT(tOut, 1, 300))
	Do $$$AssertEquals(tList.%Get(0).reason, "test row 7", "newest first")
	Do $$$AssertEquals(tList.%Get(0).loinc, "2345-7")
	Set tOut = ##class(AgenticProd.Tools.Base).%New().GetSimilarDecisions("BAD_FORMAT", ..#TESTCODE)
	Do $$$AssertEquals([].%FromJSON($PIECE(tOut, $CHAR(10), 2)).%Size(), 0, "other error class")
}

/// Empty sourceCode means any code. IRIS binds "" as NULL, which broke the first version.
Method TestGetSimilarDecisionsAnyCode()
{
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tRow.HeaderId = -9300
	Set tRow.Decision = "MAP_CODE"
	Set tRow.ErrorClass = "UNMAPPED_CODE"
	Set tRow.LocalCode = ..#TESTCODE
	Set tRow.Reason = "any code row"
	Do $$$AssertStatusOK(tRow.%Save())
	Set tOut = ##class(AgenticProd.Tools.Base).%New().GetSimilarDecisions("UNMAPPED_CODE", "")
	Set tList = [].%FromJSON($PIECE(tOut, $CHAR(10), 2))
	Do $$$AssertTrue(tList.%Size() > 0, "empty sourceCode matches any code: "_$EXTRACT(tOut, 1, 300))
	Do $$$AssertEquals(tList.%Get(0).reason, "any code row", "newest first")
}

Method OnBeforeAllTests() As %Status
{
	// Rows left by an aborted run would break the "last 5" and "newest first" checks
	Do ..DeleteTestRows()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteTestRows()
	Quit ##class(AgenticProd.Test.Tools.HL7Test).Cleanup()
}

ClassMethod DeleteTestRows() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE LocalCode = ?", ..#TESTCODE)
}

}
