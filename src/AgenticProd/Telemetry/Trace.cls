/// OpenTelemetry spans for the triage flow through %Trace. Export is native (libirisotel, OTLP/HTTP):
/// the endpoint comes from OTEL_EXPORTER_OTLP_ENDPOINT in the container environment, not from here.
/// One trace per failed message; jobs pass the parent on as a W3C traceparent string.
/// Attributes hold IDs, classes and counts only, never message text.
/// Every method accepts "" for a span or parent and never throws: tracing must not break a message.
Class AgenticProd.Telemetry.Trace Extends %RegisteredObject
{

Parameter TRACER = "AgenticProd";

Parameter VERSION = 1.0;

/// Start span pName. pParent is a traceparent string ("" = new trace); pStart is $ZTS format
/// ("" = now). pAttrs(key) = value. Returns "" if the span could not be started.
ClassMethod Start(pName As %String, pParent As %String = "", ByRef pAttrs, pStart As %String = "", pKind As %String = "Internal") As %Trace.AbstractSpan
{
	Set tSpan = ""
	Try {
		Set tTracer = ..Provider().GetTracer(..#TRACER, ..#VERSION)
		Set tCtx = ""
		If pParent '= "" {
			Set tHeaders("traceparent") = pParent
			// HttpExtract fills a clone of the context it is given; an invalid parent comes back as is
			Set tCtx = ##class(%Trace.Propagation).HttpExtract(.tHeaders, ##class(%Trace.Context).GetCurrentContext())
		}
		Set tSpan = tTracer.StartSpan(pName, tCtx, pKind, .pAttrs, $SELECT(pStart '= "": pStart, 1: $ZTIMESTAMP))
	} Catch ex {
		Set tSpan = ""
	}
	Quit tSpan
}

/// Add pAttrs, set pStatus (Ok or Error) and end pSpan. pEnd is $ZTS format ("" = now).
ClassMethod End(pSpan As %Trace.AbstractSpan, pStatus As %String = "Ok", ByRef pAttrs, pEnd As %String = "")
{
	Quit:'$IsObject(pSpan)
	Try {
		Set tKey = ""
		For {
			Set tKey = $ORDER(pAttrs(tKey), 1, tValue)
			Quit:tKey=""
			Do pSpan.Attributes.SetAt(tValue, tKey)
		}
		Do pSpan.SetStatus(pStatus)
		Set:pEnd="" pEnd = $ZTIMESTAMP
		If ..Capturing() {
			Do ..Record(pSpan, pStatus, pEnd)
		} Else {
			Do pSpan.End(pEnd)
		}
	} Catch ex {
	}
}

/// traceparent of pSpan for child spans in other jobs; "" if pSpan has no valid context.
ClassMethod Context(pSpan As %Trace.AbstractSpan) As %String
{
	Quit:'$IsObject(pSpan) ""
	Quit:'$IsObject(pSpan.Context) ""
	Quit $SELECT(pSpan.Context.IsValid(): pSpan.Context.ToString(), 1: "")
}

/// Root span "triage <control id>" for one failed message, plus its "router check" child when
/// LabRouter stamped RouterStart/RouterEnd. The root starts at RouterStart so the child fits in it.
ClassMethod TriageRoot(pRequest As AgenticProd.Msg.TriageRequest) As %Trace.AbstractSpan
{
	Set tAttrs("agentic.header_id") = pRequest.HeaderId
	Set tAttrs("agentic.session_id") = pRequest.SessionId
	Set tAttrs("agentic.format") = pRequest.Format
	Set tAttrs("agentic.injection_flagged") = ''pRequest.Flags.Count()
	Set tRoot = ..Start("triage "_$SELECT(pRequest.ControlId '= "": pRequest.ControlId, 1: pRequest.HeaderId), , .tAttrs, pRequest.RouterStart, "Server")
	If pRequest.RouterStart '= "" {
		Set tCheck("agentic.component") = "LabRouter"
		Set tCheck("agentic.error_class") = pRequest.ErrorClass
		// Count of problems, not their text: the text quotes field values
		Set tCheck("agentic.error_count") = $SELECT(pRequest.ErrorText = "": 0, 1: $LENGTH(pRequest.ErrorText, "; "))
		Set tCheck("agentic.flag_count") = pRequest.Flags.Count()
		Set tSpan = ..Start("router check", ..Context(tRoot), .tCheck, pRequest.RouterStart)
		// Ok: the router did its job; the failure it found is in agentic.error_class
		Do ..End(tSpan, "Ok", , pRequest.RouterEnd)
	}
	Quit tRoot
}

/// "agent run" span from pStart to pEnd ($ZTS: Triage's wait for the agent), built after the run
/// from pDecision and the run's Data.Usage row, plus one "execute_tool <name>" span per Data.ToolCall
/// row of that session. Built here, not in the agent job, so the agent job loads no OTel library.
/// pError is set when the agent gave no decision. A replay ran no tools, so it gets no tool spans.
ClassMethod AgentSpans(pParent As %String, pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pStart As %String, pEnd As %String, pError As %String = "")
{
	Quit:pParent=""
	Try {
		Set tAttrs("gen_ai.operation.name") = "invoke_agent"
		Set tAttrs("gen_ai.provider.name") = ##class(AgenticProd.Agent.TriageAgent).#PROVIDER
		Set tAttrs("gen_ai.agent.name") = "TriageAgent"
		Set tAttrs("agentic.header_id") = pRequest.HeaderId
		Set tAttrs("agentic.injection_flagged") = ''pRequest.Flags.Count()
		If $IsObject(pDecision) {
			Set tAttrs("agentic.decision") = pDecision.Decision
			Set tAttrs("agentic.error_class") = pDecision.ErrorClass
			Set tAttrs("agentic.confidence") = pDecision.Confidence
			Set:pDecision.Model'="" tAttrs("gen_ai.request.model") = pDecision.Model
		}
		// Usage rows are written by the agent job for this header; the latest one is this run's
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Model, PromptTokens, CompletionTokens, ReasoningTokens, ToolCalls, CostUsd, Replay, AgentSessionId FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND CreatedAt >= ? ORDER BY ID DESC", pRequest.HeaderId, $ZDATETIME($PIECE(..ZtsAdd(pStart, -1000), "."), 3))
		Set tSession = "", tReplay = 0, tToolCalls = 0
		If tRS.%Next() {
			Set tAttrs("gen_ai.request.model") = tRS.Model
			Set tAttrs("gen_ai.usage.input_tokens") = +tRS.PromptTokens
			Set tAttrs("gen_ai.usage.output_tokens") = +tRS.CompletionTokens
			Set tAttrs("agentic.reasoning_tokens") = +tRS.ReasoningTokens
			Set tToolCalls = +tRS.ToolCalls, tAttrs("agentic.tool_calls") = tToolCalls
			Set tAttrs("agentic.cost_usd") = +tRS.CostUsd
			Set tReplay = +tRS.Replay, tAttrs("agentic.replay") = tReplay
			Set tSession = tRS.AgentSessionId
			Set:tSession'="" tAttrs("gen_ai.conversation.id") = tSession
		}
		Set:pError'="" tAttrs("error.type") = "agent_error"
		Set tSpan = ..Start("agent run", pParent, .tAttrs, pStart, "Client")
		Set tAgent = ..Context(tSpan)
		If (tAgent '= "") && (tSession '= "") && 'tReplay {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, Status, DurationMs, ResultLength, CreatedAt FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? ORDER BY ID", tSession)
			Set tAudited = 0
			While tRS.%Next() {
				Set tAudited = tAudited + 1
				Do ..ToolSpan(tAgent, tRS.Tool, +tRS.DurationMs, tRS.Status, tRS.ResultLength, ..Clamp($ZDATETIMEH(tRS.CreatedAt, 3), pStart, pEnd), pStart)
			}
			// AI Hub's built-in load_skill runs outside the audit policy, so it has no ToolCall row
			Set tEnd("agentic.unaudited_tool_calls") = tToolCalls - tAudited
		}
		Do ..End(tSpan, $SELECT(pError '= "": "Error", 1: "Ok"), .tEnd, pEnd)
	} Catch ex {
	}
}

/// One finished tool call under the "agent run" span, ending at pEnd ($ZTS) and starting pDurationMs
/// before it, but not before pFloor. pStatus is Policy.Audit's OK, ERROR or DENIED.
ClassMethod ToolSpan(pParent As %String, pTool As %String, pDurationMs As %Integer, pStatus As %String, pResultLength As %Integer = "", pEnd As %String, pFloor As %String = "")
{
	Quit:pParent=""
	Set tAttrs("gen_ai.operation.name") = "execute_tool"
	Set tAttrs("gen_ai.tool.name") = pTool
	Set tAttrs("agentic.tool_status") = pStatus
	Set:pResultLength'="" tAttrs("agentic.result_length") = pResultLength
	Set tStart = ..ZtsAdd(pEnd, -pDurationMs)
	Set:(pFloor'="")&&(..ZtsDiff(tStart, pFloor)<0) tStart = pFloor
	Set tSpan = ..Start("execute_tool "_pTool, pParent, .tAttrs, tStart)
	Do ..End(tSpan, $SELECT(pStatus = "OK": "Ok", 1: "Error"), , pEnd)
}

/// "triage decision" span from pStart to now: the action matrix and what Triage did.
ClassMethod DecisionSpan(pParent As %String, pAgent As AgenticProd.Msg.Decision, pFinal As AgenticProd.Msg.Decision, pOutcome As %String, pStart As %String, pFailed As %Boolean = 0)
{
	Quit:pParent=""
	Set tAttrs("agentic.agent_decision") = $SELECT($IsObject(pAgent): pAgent.Decision, 1: "")
	Set tAttrs("agentic.decision") = $SELECT($IsObject(pFinal): pFinal.Decision, 1: "")
	Set tAttrs("agentic.error_class") = $SELECT($IsObject(pFinal): pFinal.ErrorClass, 1: "")
	Set tAttrs("agentic.final_outcome") = pOutcome
	Set tSpan = ..Start("triage decision", pParent, .tAttrs, pStart)
	Do ..End(tSpan, $SELECT(pFailed: "Error", 1: "Ok"))
}

/// "workflow review" span under the root, from when the task was logged (pLoggedAt, UTC
/// %TimeStamp) to now.
ClassMethod ReviewSpan(pParent As %String, pLoggedAt As %String, pAction As %String, pOutcome As %String, pDecision As %String)
{
	Quit:pParent=""
	Set tStart = ""
	Try {
		Set:pLoggedAt'="" tStart = $ZDATETIMEH(pLoggedAt, 3)
	} Catch ex {
	}
	Set tAttrs("agentic.review_action") = pAction
	Set tAttrs("agentic.decision") = pDecision
	Set tAttrs("agentic.final_outcome") = pOutcome
	Set tSpan = ..Start("workflow review", pParent, .tAttrs, tStart)
	Do ..End(tSpan)
}

/// TracerProvider with service.name from OTEL_SERVICE_NAME; every span is sampled.
ClassMethod Provider() As %Trace.TracerProvider
{
	// build 154: libirisotel drops the first resource attribute and sends the next as bool true,
	// so only service.name is set and the collector's resource processor sets it again
	Set tAttrs("service.name") = $SYSTEM.Util.GetEnviron("OTEL_SERVICE_NAME")
	Set:tAttrs("service.name")="" tAttrs("service.name") = "iris-agentic-production"
	Quit ##class(%Trace.TracerProvider).%New(.tAttrs, ##class(%Trace.AlwaysOnSampler).%New())
}

/// $ZTS format, pMs milliseconds before now.
ClassMethod ZtsBefore(pMs As %Integer) As %String
{
	Quit ..ZtsAdd($ZTIMESTAMP, -pMs)
}

/// pZts ($ZTS format) plus pMs milliseconds (may be negative).
ClassMethod ZtsAdd(pZts As %String, pMs As %Numeric) As %String
{
	Set tDay = +pZts, tSec = $PIECE(pZts, ",", 2) + (pMs / 1000)
	While tSec < 0 {
		Set tSec = tSec + 86400, tDay = tDay - 1
	}
	While tSec >= 86400 {
		Set tSec = tSec - 86400, tDay = tDay + 1
	}
	Quit tDay_","_$JUSTIFY(tSec, 0, 3)
}

/// pA - pB in seconds, both $ZTS format.
ClassMethod ZtsDiff(pA As %String, pB As %String) As %Numeric
{
	Quit ((+pA - +pB) * 86400) + $PIECE(pA, ",", 2) - $PIECE(pB, ",", 2)
}

/// pZts moved inside pLow..pHigh. ToolCall.CreatedAt has whole seconds, so it can fall just
/// outside the agent span.
ClassMethod Clamp(pZts As %String, pLow As %String, pHigh As %String) As %String
{
	Quit:..ZtsDiff(pZts, pLow)<0 pLow
	Quit:..ZtsDiff(pZts, pHigh)>0 pHigh
	Quit pZts
}

/// Unit tests: with capture on, End records spans in ^||AgenticProd.Trace instead of exporting.
/// Turning it on clears what was recorded.
ClassMethod Capture(pOn As %Boolean = 1)
{
	Kill ^||AgenticProd.Trace
	Set:pOn ^||AgenticProd.Trace = 0
}

ClassMethod Capturing() As %Boolean
{
	Quit $DATA(^||AgenticProd.Trace)#2
}

/// Captured spans as [{name, trace_id, span_id, parent_span_id, status, attributes:{}}].
ClassMethod Captured() As %DynamicArray
{
	Set tList = []
	For i = 1:1:$GET(^||AgenticProd.Trace) Do tList.%Push({}.%FromJSON(^||AgenticProd.Trace(i)))
	Quit tList
}

ClassMethod Record(pSpan As %Trace.AbstractSpan, pStatus As %String, pEnd As %String) [ Internal ]
{
	Set tAttrs = {}, tKey = ""
	For {
		Set tValue = pSpan.Attributes.GetNext(.tKey)
		Quit:tKey=""
		Do tAttrs.%Set(tKey, tValue)
	}
	Set tParent = $SELECT($IsObject(pSpan.Parent): pSpan.Parent.SpanId, 1: "")
	Set tEntry = {"name":(pSpan.Name), "trace_id":(pSpan.Context.TraceId), "span_id":(pSpan.Context.SpanId), "parent_span_id":(tParent), "status":(pStatus), "start":(pSpan.StartTime), "end":(pEnd), "attributes":(tAttrs)}
	Set ^||AgenticProd.Trace($INCREMENT(^||AgenticProd.Trace)) = tEntry.%ToJSON()
}

}
