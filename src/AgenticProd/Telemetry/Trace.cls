Include Ensemble

/// Trace spans for the triage flow. Every span is stored in Data.Span; it is also exported over
/// OTLP (%Trace, native libirisotel) when the trace was started with export on. The OTLP endpoint
/// comes from OTEL_EXPORTER_OTLP_ENDPOINT in the container environment, not from here.
/// One trace per failed message; jobs pass the parent on as a W3C traceparent string whose flags
/// carry the export choice (01 exported, 00 stored only).
/// Attributes hold IDs, classes and counts only, never message text.
/// Every method accepts "" for a span or parent and never throws: tracing must not break a message.
Class AgenticProd.Telemetry.Trace Extends %RegisteredObject
{

Parameter TRACER = "AgenticProd";

Parameter VERSION = 1.0;

/// Start span pName. pParent is a traceparent string ("" = new trace); pStart is $ZTS format
/// ("" = now). pAttrs(key) = value. pExport applies to a new trace only; a child follows its
/// parent's flags. Returns "" if the span could not be started.
ClassMethod Start(pName As %String, pParent As %String = "", ByRef pAttrs, pStart As %String = "", pKind As %String = "Internal", pExport As %Boolean = 0) As AgenticProd.Telemetry.Span
{
	Set tSpan = ""
	Try {
		Set:pStart="" pStart = $ZTIMESTAMP
		Set tParentTrace = "", tParentSpan = ""
		If pParent '= "" {
			Quit:'$MATCH(pParent, "(?i)00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}")
			Set tParentTrace = $PIECE(pParent, "-", 2), tParentSpan = $PIECE(pParent, "-", 3)
			Set pExport = ($PIECE(pParent, "-", 4) = "01")
		}
		Set tSpan = ##class(AgenticProd.Telemetry.Span).%New()
		Set tSpan.Name = pName, tSpan.Start = pStart, tSpan.ParentSpanId = tParentSpan
		Set tSpan.Attributes = {}, tKey = ""
		For {
			Set tKey = $ORDER(pAttrs(tKey), 1, tValue)
			Quit:tKey=""
			Do tSpan.Attributes.%Set(tKey, tValue)
		}
		If pExport && '..Capturing() Set tSpan.Native = ..StartNative(pName, pParent, .pAttrs, pStart, pKind)
		If $IsObject(tSpan.Native) {
			Set tSpan.TraceId = tSpan.Native.Context.TraceId, tSpan.SpanId = tSpan.Native.Context.SpanId
		} Else {
			// Export off, or the exporter failed: the span is still stored
			Set tSpan.TraceId = $SELECT(tParentTrace '= "": tParentTrace, 1: ..HexId(16)), tSpan.SpanId = ..HexId(8)
		}
		Set tKeys = $GET(^||AgenticProd.SpanKeys(tSpan.TraceId))
		Set tSpan.HeaderId = $LISTGET(tKeys, 1), tSpan.ControlId = $LISTGET(tKeys, 2)
	} Catch ex {
		Set tSpan = ""
		Do ..LogError("start "_pName, ex)
	}
	Quit tSpan
}

/// %Trace span for an exported trace; "" when it could not be started.
ClassMethod StartNative(pName As %String, pParent As %String, ByRef pAttrs, pStart As %String, pKind As %String) As %Trace.AbstractSpan [ Internal ]
{
	Set tNative = ""
	Try {
		Set tTracer = ..Provider().GetTracer(..#TRACER, ..#VERSION)
		Set tCtx = ""
		If pParent '= "" {
			Set tHeaders("traceparent") = pParent
			// HttpExtract fills a clone of the context it is given; an invalid parent comes back as is
			Set tCtx = ##class(%Trace.Propagation).HttpExtract(.tHeaders, ##class(%Trace.Context).GetCurrentContext())
		}
		Set tNative = tTracer.StartSpan(pName, tCtx, pKind, .pAttrs, pStart)
		Set:'$IsObject(tNative) tNative = ""
		Set:$IsObject(tNative)&&'tNative.Context.IsValid() tNative = ""
	} Catch ex {
		Set tNative = ""
		Do ..LogError("export "_pName, ex)
	}
	Quit tNative
}

/// Add pAttrs, set pStatus (Ok or Error), end pSpan and store it in Data.Span. pEnd is $ZTS
/// format ("" = now).
ClassMethod End(pSpan As AgenticProd.Telemetry.Span, pStatus As %String = "Ok", ByRef pAttrs, pEnd As %String = "")
{
	Quit:'$IsObject(pSpan)
	Try {
		Set:pEnd="" pEnd = $ZTIMESTAMP
		Set tKey = ""
		For {
			Set tKey = $ORDER(pAttrs(tKey), 1, tValue)
			Quit:tKey=""
			Do pSpan.Attributes.%Set(tKey, tValue)
			Do:$IsObject(pSpan.Native) pSpan.Native.Attributes.SetAt(tValue, tKey)
		}
		If $IsObject(pSpan.Native) {
			Do pSpan.Native.SetStatus(pStatus)
			Do pSpan.Native.End(pEnd)
		}
		Do:..Capturing() ..Record(pSpan, pStatus, pEnd)
		Do ..Store(pSpan, pStatus, pEnd)
	} Catch ex {
		Do ..LogError("end "_pSpan.Name, ex)
	}
}

/// Write pSpan to Data.Span. A span ended in another job than its root (workflow review) takes
/// the header and control ID from the trace's spans already stored.
ClassMethod Store(pSpan As AgenticProd.Telemetry.Span, pStatus As %String, pEnd As %String) [ Internal ]
{
	Try {
		If pSpan.HeaderId = "" {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 HeaderId, ControlId FROM AgenticProd_Data.Span WHERE TraceId = ? AND HeaderId IS NOT NULL", pSpan.TraceId)
			If tRS.%Next() Set pSpan.HeaderId = tRS.HeaderId, pSpan.ControlId = tRS.ControlId
		}
		$$$ThrowOnError(##class(AgenticProd.Data.Span).Log(pSpan.TraceId, pSpan.SpanId, pSpan.ParentSpanId, pSpan.Name, pSpan.Start, pEnd, pStatus, pSpan.Attributes, pSpan.HeaderId, pSpan.ControlId, $IsObject(pSpan.Native)))
	} Catch ex {
		Do ..LogError("store "_pSpan.Name, ex)
	}
}

/// Tracing never fails a message, so its errors only go to the event log.
ClassMethod LogError(pWhat As %String, pEx As %Exception.AbstractException) [ Internal ]
{
	Try {
		$$$LOGWARNING("Telemetry.Trace "_pWhat_": "_pEx.DisplayString())
	} Catch {
	}
}

/// pBytes random bytes as lowercase hex (W3C IDs: 16 for a trace, 8 for a span).
ClassMethod HexId(pBytes As %Integer) As %String [ Internal ]
{
	Set tRaw = $SYSTEM.Encryption.GenCryptRand(pBytes), tHex = ""
	For i = 1:1:pBytes Set tHex = tHex_$ZCONVERT($TRANSLATE($JUSTIFY($ZHEX($ASCII(tRaw, i)), 2), " ", "0"), "L")
	Quit tHex
}

/// traceparent of pSpan for child spans in other jobs; "" if pSpan is not a span.
ClassMethod Context(pSpan As AgenticProd.Telemetry.Span) As %String
{
	Quit:'$IsObject(pSpan) ""
	Quit pSpan.Context()
}

/// Root span "triage <control id>" for one failed message, plus its "router check" child when
/// LabRouter stamped RouterStart/RouterEnd. The root starts at RouterStart so the child fits in it.
/// pExport = 1 also sends the whole trace over OTLP.
ClassMethod TriageRoot(pRequest As AgenticProd.Msg.TriageRequest, pExport As %Boolean = 0) As AgenticProd.Telemetry.Span
{
	Set tAttrs("agentic.header_id") = pRequest.HeaderId
	Set tAttrs("agentic.session_id") = pRequest.SessionId
	Set tAttrs("agentic.format") = pRequest.Format
	Set tAttrs("agentic.injection_flagged") = ''pRequest.Flags.Count()
	Set tRoot = ..Start("triage "_$SELECT(pRequest.ControlId '= "": pRequest.ControlId, 1: pRequest.HeaderId), , .tAttrs, pRequest.RouterStart, "Server", pExport)
	Quit:'$IsObject(tRoot) ""
	// Spans started later in this job (agent run, tools, decision) are stored with these keys
	Set tRoot.HeaderId = pRequest.HeaderId, tRoot.ControlId = pRequest.ControlId
	Set ^||AgenticProd.SpanKeys(tRoot.TraceId) = $LISTBUILD(pRequest.HeaderId, pRequest.ControlId)
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
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Model, PromptTokens, CompletionTokens, ReasoningTokens, ToolCalls, CostUsd, Replay, AgentSessionId FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND Namespace = ? AND CreatedAt >= ? ORDER BY ID DESC", pRequest.HeaderId, $NAMESPACE, $ZDATETIME($PIECE(..ZtsAdd(pStart, -1000), "."), 3))
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
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, Status, DurationMs, ResultLength, CreatedAt FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? ORDER BY ID", tSession, $NAMESPACE)
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
/// pGrounding (Triage.Ground) adds agentic.grounded and agentic.grounding_failures.
ClassMethod DecisionSpan(pParent As %String, pAgent As AgenticProd.Msg.Decision, pFinal As AgenticProd.Msg.Decision, pOutcome As %String, pStart As %String, pFailed As %Boolean = 0, pGrounding As %DynamicObject = "")
{
	Quit:pParent=""
	If $IsObject(pGrounding) {
		Set tAttrs("agentic.grounded") = $SELECT(pGrounding.grounded: "true", 1: "false")
		Set tAttrs("agentic.grounding_failures") = pGrounding.failed
	}
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

/// Unit tests: with capture on, End also records spans in ^||AgenticProd.Trace and nothing is
/// exported. Turning it on clears what was recorded.
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

ClassMethod Record(pSpan As AgenticProd.Telemetry.Span, pStatus As %String, pEnd As %String) [ Internal ]
{
	Set tEntry = {"name":(pSpan.Name), "trace_id":(pSpan.TraceId), "span_id":(pSpan.SpanId), "parent_span_id":(pSpan.ParentSpanId), "status":(pStatus), "start":(pSpan.Start), "end":(pEnd), "attributes":(pSpan.Attributes)}
	Set ^||AgenticProd.Trace($INCREMENT(^||AgenticProd.Trace)) = tEntry.%ToJSON()
}

}
