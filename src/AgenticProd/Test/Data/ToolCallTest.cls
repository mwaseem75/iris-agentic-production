/// Unit tests for AgenticProd.Data.ToolCall.
Class AgenticProd.Test.Data.ToolCallTest Extends %UnitTest.TestCase
{

Method TestLog()
{
	Set tSC = ##class(AgenticProd.Data.ToolCall).Log("get_error_events", {"header_id":-1}, "OK", 12, 340, , -1, "unittest", .tId)
	Do $$$AssertStatusOK(tSC, "allowed call logged")
	Set tRow = ##class(AgenticProd.Data.ToolCall).%OpenId(tId)
	Do $$$AssertTrue($IsObject(tRow), "row exists")
	Quit:'$IsObject(tRow)
	Do $$$AssertEquals(tRow.Arguments, "{""header_id"":-1}", "dynamic object stored as JSON")
	Do $$$AssertEquals(tRow.DurationMs, 12)
	Do ##class(AgenticProd.Data.ToolCall).%DeleteId(tId)

	Set tSC = ##class(AgenticProd.Data.ToolCall).Log("apply_fix", "{}", "DENIED", , , "REQUIRESAUTH tool", -1, "unittest", .tId)
	Do $$$AssertStatusOK(tSC, "denied call logged")
	Do:tId'="" ##class(AgenticProd.Data.ToolCall).%DeleteId(tId)

	Set tSC = ##class(AgenticProd.Data.ToolCall).Log("x", "{}", "MAYBE", , , , -1, , .tId)
	Do $$$AssertStatusNotOK(tSC, "unknown status rejected")
}

}
