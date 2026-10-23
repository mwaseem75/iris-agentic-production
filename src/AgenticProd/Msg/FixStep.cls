/// One proposed change in a Decision's fix list: set the value at Path from FromValue to ToValue.
Class AgenticProd.Msg.FixStep Extends (%SerialObject, %JSON.Adaptor)
{

/// Format-specific location, e.g. "OBX(1):5" for HL7 or a FHIRPath for FHIR.
Property Path As %String(%JSONFIELDNAME = "path", MAXLEN = 500);

Property FromValue As %String(%JSONFIELDNAME = "from", MAXLEN = "");

Property ToValue As %String(%JSONFIELDNAME = "to", MAXLEN = "");

Storage Default
{
<Data name="FixStepState">
<Value name="1">
<Value>Path</Value>
</Value>
<Value name="2">
<Value>FromValue</Value>
</Value>
<Value name="3">
<Value>ToValue</Value>
</Value>
</Data>
<State>FixStepState</State>
<StreamLocation>^AgenticProd.Msg.FixStepS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
