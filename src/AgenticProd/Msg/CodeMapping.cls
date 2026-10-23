/// Proposed local code to LOINC mapping in a MAP_CODE decision.
Class AgenticProd.Msg.CodeMapping Extends (%SerialObject, %JSON.Adaptor)
{

Property LocalCode As %String(%JSONFIELDNAME = "local_code", MAXLEN = 100);

Property Loinc As %String(%JSONFIELDNAME = "loinc", MAXLEN = 20);

Property Display As %String(%JSONFIELDNAME = "display", MAXLEN = 500);

Storage Default
{
<Data name="CodeMappingState">
<Value name="1">
<Value>LocalCode</Value>
</Value>
<Value name="2">
<Value>Loinc</Value>
</Value>
<Value name="3">
<Value>Display</Value>
</Value>
</Data>
<State>CodeMappingState</State>
<StreamLocation>^AgenticProd.Msg.CodeMappingS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
