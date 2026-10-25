Include (%AI, Ensemble)

/// Global audit policy for the triage agent: one Data.ToolCall row per tool call, allowed or
/// denied, plus a $$$TRACE line so the call shows in Visual Trace.
/// Operation.Agent sets HeaderId and AgentSessionId before the agent runs.
Class AgenticProd.Policy.Audit Extends %AI.Policy.Audit
{

Property HeaderId As %Integer;

Property AgentSessionId As %String(MAXLEN = 50);

/// traceparent of the "agent run" span; "" when tracing is off. Each call becomes a child span.
Property TraceParent As %String(MAXLEN = 60);

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
	Set tResultLength = ""
	If $IsObject(result) Set tResultLength = $LENGTH(result.%Get("result_json"))
	Set tError = $SELECT($$$ISERR(status): $SYSTEM.Status.GetErrorText(status), 1: "")
	// call.name is the requested tool; note a redirect by an auth policy
	If $IsObject(result), result.%Get("tool_name") '= "", result.%Get("tool_name") '= call.name {
		Set tError = "redirected to "_result.%Get("tool_name")_$SELECT(tError '= "": "; "_tError, 1: "")
	}
	Set tStatus = $SELECT($$$ISERR(status): "ERROR", 1: "OK")
	$$$TRACE("Tool "_call.name_" "_tStatus_" ms="_duration_" resultLength="_tResultLength_$SELECT(tError '= "": " "_tError, 1: ""))
	Do ##class(AgenticProd.Telemetry.Trace).ToolSpan(..TraceParent, call.name, duration, tStatus, tResultLength)
	Quit ##class(AgenticProd.Data.ToolCall).Log(call.name, call.arguments, tStatus, duration, tResultLength, tError, ..HeaderId, ..AgentSessionId)
}

Method %LogDenial(call As %DynamicObject, metadata As %DynamicObject, status As %Status) As %Status
{
	Set tError = $SYSTEM.Status.GetErrorText(status)
	$$$TRACE("Tool "_call.name_" DENIED: "_tError)
	Do ##class(AgenticProd.Telemetry.Trace).ToolSpan(..TraceParent, call.name, 0, "DENIED")
	Quit ##class(AgenticProd.Data.ToolCall).Log(call.name, call.arguments, "DENIED", "", "", tError, ..HeaderId, ..AgentSessionId)
}

}
