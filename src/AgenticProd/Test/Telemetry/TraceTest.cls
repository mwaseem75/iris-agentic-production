/// Telemetry.Trace with capture on: span names, parent links and attributes for one failed message,
/// recorded in-process instead of exported. Needs libirisotel (in the build 154 image). No LLM.
Class AgenticProd.Test.Telemetry.TraceTest Extends %UnitTest.TestCase
{

/// Planted in the error text; no attribute may carry it.
Parameter MARKER = "PHI-MARKER-7731";

Method OnAfterOneTest() As %Status
{
	Do ##class(AgenticProd.Telemetry.Trace).Capture(0)
	Quit $$$OK
}

Method TestTriageTraceTree()
{
	Do ##class(AgenticProd.Telemetry.Trace).Capture(1)
	Set tRequest = ..Request()

	Set tRoot = ##class(AgenticProd.Telemetry.Trace).TriageRoot(tRequest)
	Set tRequest.TraceParent = ##class(AgenticProd.Telemetry.Trace).Context(tRoot)
	Do $$$AssertTrue(tRequest.TraceParent ? 1"00-"32AN1"-"16AN1"-0"1N, "root traceparent is W3C: "_tRequest.TraceParent)

	Set tAgent = ##class(AgenticProd.Telemetry.Trace).AgentStart(tRequest, "gpt-4o-mini", "replay")
	Do ##class(AgenticProd.Telemetry.Trace).ToolSpan(##class(AgenticProd.Telemetry.Trace).Context(tAgent), "get_failed_message", 40, "OK", 812)
	Do ##class(AgenticProd.Telemetry.Trace).ToolSpan(##class(AgenticProd.Telemetry.Trace).Context(tAgent), "apply_fix", 0, "DENIED")
	Set tDecision = ##class(AgenticProd.Msg.Decision).%New()
	Set tDecision.Decision = "AUTO_FIX", tDecision.ErrorClass = "BAD_FORMAT", tDecision.Confidence = .92
	Set tDecision.PromptTokens = 1200, tDecision.CompletionTokens = 150, tDecision.CostUsd = .00027
	Set tDecision.Reason = ..#MARKER
	Set tUsage = ##class(AgenticProd.Data.Usage).%New()
	Set tUsage.ReasoningTokens = 64, tUsage.ToolCalls = 2
	Do ##class(AgenticProd.Telemetry.Trace).AgentEnd(tAgent, tDecision, tUsage)

	Set tFinal = tDecision.Escalated("downgraded from AUTO_FIX: suspicious instruction")
	Do ##class(AgenticProd.Telemetry.Trace).DecisionSpan(tRequest.TraceParent, tDecision, tFinal, "DOWNGRADED:AUTO_FIX", $ZTIMESTAMP)
	Do ##class(AgenticProd.Telemetry.Trace).ReviewSpan(tRequest.TraceParent, $ZDATETIME($ZTIMESTAMP, 3), "Approve", "REVIEW_CLOSED", "ESCALATE")
	Set tAttrs("agentic.final_outcome") = "DOWNGRADED:AUTO_FIX"
	Do ##class(AgenticProd.Telemetry.Trace).End(tRoot, "Ok", .tAttrs)

	Set tSpans = ##class(AgenticProd.Telemetry.Trace).Captured()
	For i = 0:1:tSpans.%Size() - 1 Set tByName(tSpans.%Get(i).name) = tSpans.%Get(i)
	For tName = "triage EV1-05","router check","agent run","execute_tool get_failed_message","execute_tool apply_fix","triage decision","workflow review" {
		Do $$$AssertTrue($DATA(tByName(tName)), "span '"_tName_"' recorded")
	}
	Quit:tSpans.%Size()'=7

	Set tRootSpan = tByName("triage EV1-05"), tAgentSpan = tByName("agent run")
	Do $$$AssertEquals(tRootSpan."parent_span_id", "", "root has no parent")
	For tName = "router check","agent run","triage decision","workflow review" {
		Do $$$AssertEquals(tByName(tName)."parent_span_id", tRootSpan."span_id", tName_" is a child of the root")
	}
	Do $$$AssertEquals(tByName("execute_tool get_failed_message")."parent_span_id", tAgentSpan."span_id", "tool span is a child of agent run")
	For i = 0:1:tSpans.%Size() - 1 Do $$$AssertEquals(tSpans.%Get(i)."trace_id", tRootSpan."trace_id", "one trace: "_tSpans.%Get(i).name)

	Set tA = tAgentSpan.attributes
	Do $$$AssertEquals(tA.%Get("gen_ai.operation.name"), "invoke_agent")
	Do $$$AssertEquals(tA.%Get("gen_ai.provider.name"), "openai")
	Do $$$AssertEquals(tA.%Get("gen_ai.request.model"), "gpt-4o-mini")
	Do $$$AssertEquals(tA.%Get("gen_ai.usage.input_tokens"), 1200)
	Do $$$AssertEquals(tA.%Get("gen_ai.usage.output_tokens"), 150)
	Do $$$AssertEquals(tA.%Get("agentic.decision"), "AUTO_FIX")
	Do $$$AssertEquals(tA.%Get("agentic.cost_usd"), .00027)
	Do $$$AssertEquals(tA.%Get("agentic.reasoning_tokens"), 64)
	Do $$$AssertEquals(tA.%Get("agentic.injection_flagged"), 1)

	Set tTool = tByName("execute_tool get_failed_message").attributes
	Do $$$AssertEquals(tTool.%Get("gen_ai.tool.name"), "get_failed_message")
	Do $$$AssertEquals(tTool.%Get("gen_ai.operation.name"), "execute_tool")
	Do $$$AssertEquals(tByName("execute_tool apply_fix").status, "Error", "denied call is an error span")

	Do $$$AssertEquals(tByName("router check").attributes.%Get("agentic.error_class"), "BAD_FORMAT")
	Do $$$AssertEquals(tByName("router check").attributes.%Get("agentic.error_count"), 2)
	Do $$$AssertEquals(tByName("router check").start, tRequest.RouterStart, "router check keeps LabRouter's start")
	Do $$$AssertEquals(tRootSpan.start, tRequest.RouterStart, "root starts with the router check")
	Do $$$AssertEquals(tByName("triage decision").attributes.%Get("agentic.final_outcome"), "DOWNGRADED:AUTO_FIX")
	Do $$$AssertEquals(tByName("triage decision").attributes.%Get("agentic.decision"), "ESCALATE")
	Do $$$AssertEquals(tByName("workflow review").attributes.%Get("agentic.review_action"), "Approve")
	Do $$$AssertEquals(tRootSpan.attributes.%Get("agentic.final_outcome"), "DOWNGRADED:AUTO_FIX")

	Set tJSON = tSpans.%ToJSON()
	Do $$$AssertNotTrue(tJSON [ ..#MARKER, "no message or decision text in any attribute")
	Do $$$AssertNotTrue(tJSON [ "PATIENT", "no flag text in any attribute")
}

/// A missing span or parent is a no-op, so components need no tracing checks of their own.
Method TestNoParentNoSpan()
{
	Do ##class(AgenticProd.Telemetry.Trace).Capture(1)
	Do ##class(AgenticProd.Telemetry.Trace).ToolSpan("", "get_failed_message", 10, "OK")
	Do ##class(AgenticProd.Telemetry.Trace).DecisionSpan("", "", "", "APPLIED", $ZTIMESTAMP)
	Do ##class(AgenticProd.Telemetry.Trace).ReviewSpan("", "", "Approve", "APPROVED", "MAP_CODE")
	Do ##class(AgenticProd.Telemetry.Trace).AgentEnd("", "", "")
	Do ##class(AgenticProd.Telemetry.Trace).End("")
	Do $$$AssertEquals(##class(AgenticProd.Telemetry.Trace).Captured().%Size(), 0, "nothing recorded")
	Do $$$AssertEquals(##class(AgenticProd.Telemetry.Trace).Context(""), "")
}

Method TestZtsBefore()
{
	Set tNow = $ZTIMESTAMP
	Set tBefore = ##class(AgenticProd.Telemetry.Trace).ZtsBefore(1500)
	Set tDiff = (($PIECE(tNow, ",") - $PIECE(tBefore, ",")) * 86400) + $PIECE(tNow, ",", 2) - $PIECE(tBefore, ",", 2)
	Do $$$AssertTrue((tDiff >= 1.4) && (tDiff < 1.6), "1500 ms earlier, got "_tDiff_" s")
}

ClassMethod Request() As AgenticProd.Msg.TriageRequest
{
	Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
	Set tRequest.HeaderId = -9301, tRequest.SessionId = -9301
	Set tRequest.Format = "HL7v2", tRequest.ControlId = "EV1-05"
	Set tRequest.ErrorClass = "BAD_FORMAT"
	Set tRequest.ErrorText = "Validation: OBX(1):14 '"_..#MARKER_"' is not a valid TS; Validation: OBR(1):7 required"
	Do tRequest.Flags.Insert("NTE(1):3: PATIENT note, ai agent")
	Set tRequest.RouterStart = ##class(AgenticProd.Telemetry.Trace).ZtsBefore(30)
	Set tRequest.RouterEnd = $ZTIMESTAMP
	Quit tRequest
}

}
