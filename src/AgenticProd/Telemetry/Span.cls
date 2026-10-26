/// An open span from Telemetry.Trace.Start. Native is the %Trace span when the trace is exported;
/// with export off no %Trace object exists and libirisotel is never loaded.
Class AgenticProd.Telemetry.Span Extends %RegisteredObject
{

Property Name As %String(MAXLEN = 200);

Property TraceId As %String;

Property SpanId As %String;

Property ParentSpanId As %String;

/// $ZTS format.
Property Start As %String;

Property Attributes As %DynamicObject;

Property Native As %Trace.AbstractSpan;

Property HeaderId As %Integer;

Property ControlId As %String(MAXLEN = 200);

/// W3C traceparent for child spans; flags 01 = exported (sampled), 00 = stored in IRIS only.
Method Context() As %String
{
	Quit "00-"_..TraceId_"-"_..SpanId_"-"_$SELECT($IsObject(..Native): "01", 1: "00")
}

}
