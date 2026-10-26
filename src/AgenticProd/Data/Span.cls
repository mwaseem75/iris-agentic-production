/// One finished trace span, kept in IRIS whether or not it was exported over OTLP; never purged.
/// Written by Telemetry.Trace.End. Attributes are the span's GenAI/agentic attributes (IDs,
/// classes, counts), never message text.
Class AgenticProd.Data.Span Extends %Persistent
{

/// 32 hex characters (W3C trace-id).
Property TraceId As %String(MAXLEN = 32) [ Required ];

/// 16 hex characters (W3C span-id).
Property SpanId As %String(MAXLEN = 16) [ Required ];

Property ParentSpanId As %String(MAXLEN = 16);

Property Name As %String(MAXLEN = 200) [ Required ];

/// UTC, milliseconds.
Property StartTs As %TimeStamp;

Property EndTs As %TimeStamp;

Property DurationMs As %Integer;

/// Ok or Error.
Property Status As %String(MAXLEN = 10);

/// JSON object text.
Property Attributes As %String(MAXLEN = "");

Property HeaderId As %Integer;

Property ControlId As %String(MAXLEN = 200);

Property EvalRunId As %Integer;

/// 1 when the span also went to the OTLP exporter.
Property Exported As %Boolean [ InitialExpression = 0 ];

Index TraceIdx On TraceId;

Index HeaderIdx On HeaderId;

Index EvalRunIdx On EvalRunId;

/// Save one span. pStart and pEnd are $ZTS format; pAttrs is a %DynamicObject.
ClassMethod Log(pTraceId As %String, pSpanId As %String, pParentSpanId As %String, pName As %String, pStart As %String, pEnd As %String, pStatus As %String, pAttrs As %DynamicObject, pHeaderId As %Integer = "", pControlId As %String = "", pExported As %Boolean = 0, Output pId As %String) As %Status
{
	Set pId = ""
	Set tSC = $$$OK
	Try {
		Set tRow = ..%New()
		Set tRow.TraceId = pTraceId, tRow.SpanId = pSpanId, tRow.ParentSpanId = pParentSpanId
		Set tRow.Name = $EXTRACT(pName, 1, 200), tRow.Status = pStatus
		Set tRow.StartTs = ..Ts(pStart), tRow.EndTs = ..Ts(pEnd)
		If (pStart '= "") && (pEnd '= "") Set tRow.DurationMs = ##class(AgenticProd.Telemetry.Trace).ZtsDiff(pEnd, pStart) * 1000 \ 1
		Set tRow.Attributes = $SELECT($IsObject(pAttrs): pAttrs.%ToJSON(), 1: "{}")
		Set tRow.HeaderId = pHeaderId, tRow.ControlId = pControlId, tRow.Exported = pExported
		Do ##class(AgenticProd.Eval.Runner).CaseOf(pControlId, .tRunId)
		Set tRow.EvalRunId = tRunId
		$$$ThrowOnError(tRow.%Save())
		Set pId = tRow.%Id()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// $ZTS to %TimeStamp with milliseconds.
ClassMethod Ts(pZts As %String) As %TimeStamp [ Internal ]
{
	Quit:pZts="" ""
	Quit $ZDATETIME(pZts, 3, , 3)
}

Storage Default
{
<Data name="SpanDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>TraceId</Value>
</Value>
<Value name="3">
<Value>SpanId</Value>
</Value>
<Value name="4">
<Value>ParentSpanId</Value>
</Value>
<Value name="5">
<Value>Name</Value>
</Value>
<Value name="6">
<Value>StartTs</Value>
</Value>
<Value name="7">
<Value>EndTs</Value>
</Value>
<Value name="8">
<Value>DurationMs</Value>
</Value>
<Value name="9">
<Value>Status</Value>
</Value>
<Value name="10">
<Value>Attributes</Value>
</Value>
<Value name="11">
<Value>HeaderId</Value>
</Value>
<Value name="12">
<Value>ControlId</Value>
</Value>
<Value name="13">
<Value>EvalRunId</Value>
</Value>
<Value name="14">
<Value>Exported</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.SpanD</DataLocation>
<DefaultData>SpanDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.SpanD</IdLocation>
<IndexLocation>^AgenticProd.Data.SpanI</IndexLocation>
<StreamLocation>^AgenticProd.Data.SpanS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
