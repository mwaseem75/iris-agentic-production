/// ReadOnly and Audit policies, called directly with the call/metadata shapes AI Hub passes. No LLM.
Class AgenticProd.Test.Policy.PolicyTest Extends %UnitTest.TestCase
{

Method TestReadOnlyDeniesRequiresAuth()
{
	Set tPolicy = ##class(AgenticProd.Policy.ReadOnly).%New()
	Set tCall = {"id":"c1","name":"ApplyFix","arguments":{"headerId":1}}
	Set tMeta = {"name":"ApplyFix"}
	Do tMeta.%Set("requires_auth", 1, "boolean")
	Do $$$AssertNotTrue(tPolicy.%CanList("iris:Test", tMeta), "mutating tool is hidden")
	Set tSC = tPolicy.%CanExecute("iris:Test", tCall, tMeta)
	Do $$$AssertStatusNotOK(tSC, "mutating tool is denied")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(tSC) [ "tier write", "reason names the tier")

	Do tMeta.%Set("requires_auth", 0, "boolean")
	Do $$$AssertTrue(tPolicy.%CanList("iris:Test", tMeta), "read tool is listed")
	Do $$$AssertStatusOK(tPolicy.%CanExecute("iris:Test", tCall, tMeta), "read tool is allowed")
	Do $$$AssertStatusOK(tPolicy.%CanExecute("iris:Test", tCall, ""), "no metadata -> allowed")
}

/// Tiers from the Settings tab: refused unless enabled; requires_auth is never below write.
Method TestToolTiers()
{
	Set tPolicy = ##class(AgenticProd.Policy.ReadOnly).%New()
	Set tPolicy.ToolTiers = "get_segment=write,validate_fix=critical"
	Set tMeta = {"name":"get_segment"}
	Do tMeta.%Set("requires_auth", 0, "boolean")
	Set tCall = {"id":"c1","name":"get_segment","arguments":{}}
	Do $$$AssertEquals(tPolicy.TierOf("get_segment", tMeta), "write")
	Do $$$AssertEquals(tPolicy.TierOf("get_failed_message", tMeta), "readonly", "unlisted tool is readonly")
	Do $$$AssertNotTrue(tPolicy.%CanList("get_segment", tMeta), "write tool hidden while only readonly is enabled")
	Do $$$AssertStatusNotOK(tPolicy.%CanExecute("get_segment", tCall, tMeta))
	Do $$$AssertTrue(tPolicy.%CanList("get_failed_message", tMeta))

	Set tPolicy.EnabledTiers = "readonly,write"
	Do $$$AssertTrue(tPolicy.%CanList("get_segment", tMeta), "write enabled")
	Do $$$AssertStatusOK(tPolicy.%CanExecute("get_segment", tCall, tMeta))
	Set tCall.name = "validate_fix"
	Do $$$AssertStatusNotOK(tPolicy.%CanExecute("validate_fix", tCall, tMeta), "critical still refused")

	// A mutating tool configured as readonly stays write
	Do tMeta.%Set("requires_auth", 1, "boolean")
	Set tPolicy.EnabledTiers = "readonly"
	Do $$$AssertEquals(tPolicy.TierOf("get_failed_message", tMeta), "write")
	Do $$$AssertNotTrue(tPolicy.%CanList("get_failed_message", tMeta))
}

Method TestAuditWritesToolCallRows()
{
	Set tPolicy = ##class(AgenticProd.Policy.Audit).%New()
	Set tPolicy.HeaderId = -9101
	Set tPolicy.AgentSessionId = "test-audit"
	Set tCall = {"id":"c1","name":"GetErrorEvents","arguments":{"headerId":-9101}}
	Set tResult = {"tool_name":"GetErrorEvents","result_json":"[\"x\"]"}

	Do $$$AssertStatusOK(tPolicy.%LogExecution(tCall, {}, tResult, 12, $$$OK))
	Do $$$AssertStatusOK(tPolicy.%LogExecution(tCall, {}, "", 3, $$$ERROR($$$GeneralError, "boom")))
	Do $$$AssertStatusOK(tPolicy.%LogDenial(tCall, {}, $$$ERROR($$$GeneralError, "read-only")))

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, DurationMs, ResultLength, ErrorText, Arguments, AgentSessionId FROM AgenticProd_Data.ToolCall WHERE HeaderId = ? ORDER BY ID", -9101)
	Do $$$AssertTrue(tRS.%Next(), "OK row")
	Do $$$AssertEquals(tRS.Status, "OK")
	Do $$$AssertEquals(tRS.DurationMs, 12)
	Do $$$AssertEquals(tRS.ResultLength, 5)
	Do $$$AssertEquals(tRS.AgentSessionId, "test-audit")
	Do $$$AssertTrue(tRS.Arguments [ "-9101", "arguments stored as JSON")
	Do $$$AssertTrue(tRS.%Next(), "ERROR row")
	Do $$$AssertEquals(tRS.Status, "ERROR")
	Do $$$AssertTrue(tRS.ErrorText [ "boom")
	Do $$$AssertTrue(tRS.%Next(), "DENIED row")
	Do $$$AssertEquals(tRS.Status, "DENIED")
	Do $$$AssertEquals(tRS.DurationMs, "")
	Do $$$AssertNotTrue(tRS.%Next(), "three rows only")
}

Method OnAfterAllTests() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.ToolCall WHERE HeaderId = -9101")
	Quit $$$OK
}

}
