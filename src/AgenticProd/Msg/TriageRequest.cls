/// Request to triage one failed message. Format-neutral: it points at the failed message
/// and carries the error; the agent reads the payload itself through its tools.
Class AgenticProd.Msg.TriageRequest Extends (Ens.Request, %JSON.Adaptor)
{

/// Ens.MessageHeader ID of the failed message.
Property HeaderId As %Integer(%JSONFIELDNAME = "header_id") [ Required ];

/// Session ID of the failed message, for error events and Visual Trace.
Property SessionId As %Integer(%JSONFIELDNAME = "session_id");

/// Business host or source system the message came from.
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 128);

/// Payload format, e.g. HL7v2 or FHIR. Tells the agent which format skill to load.
Property Format As %String(%JSONFIELDNAME = "format", MAXLEN = 20);

/// Validation or processing error text that triggered triage.
Property ErrorText As %String(%JSONFIELDNAME = "error_text", MAXLEN = "");

/// The router's first guess at the error class. The agent may change it.
Property ErrorClass As AgenticProd.Msg.ErrorClass(%JSONFIELDNAME = "error_class");

/// Policy.InjectionGuard hits, one per segment field: "NTE(1): system note, ai agent".
/// Any hit means no AUTO_FIX; Triage copies them into the decision evidence for the reviewer.
Property Flags As list Of %String(%JSONFIELDNAME = "flags", MAXLEN = 500);

Storage Default
{
<Data name="TriageRequestDefaultData">
<Subscript>"TriageRequest"</Subscript>
<Value name="1">
<Value>HeaderId</Value>
</Value>
<Value name="2">
<Value>SessionId</Value>
</Value>
<Value name="3">
<Value>Source</Value>
</Value>
<Value name="4">
<Value>Format</Value>
</Value>
<Value name="5">
<Value>ErrorText</Value>
</Value>
<Value name="6">
<Value>ErrorClass</Value>
</Value>
<Value name="7">
<Value>Flags</Value>
</Value>
</Data>
<DefaultData>TriageRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
