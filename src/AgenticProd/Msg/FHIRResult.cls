/// What Operation.NphiesFHIROut did with one HL7 result: valid bundles are written, invalid ones
/// are not, and LabRouter sends them to Triage with Format FHIR.
Class AgenticProd.Msg.FHIRResult Extends Ens.Response
{

/// MSH-10 of the HL7 message; eval sends (EV<runId>-<caseId>) are left out of live counts.
Property ControlId As %String(MAXLEN = 200);

Property Valid As %Boolean;

/// Error and fatal issues only; warnings and information do not make a bundle invalid.
Property IssueCount As %Integer;

/// One line per issue, "Observation[1] Observation.valueQuantity.value: ...", for the TriageRequest.
Property Issues As %String(MAXLEN = "");

/// OperationOutcome JSON with the error issues, expressions prefixed with the bundle entry.
Property Outcome As %Stream.GlobalCharacter;

/// File written to the simulated NPHIES FHIR endpoint; empty when invalid.
Property FileName As %String(MAXLEN = 500);

Storage Default
{
<Data name="FHIRResultDefaultData">
<Subscript>"FHIRResult"</Subscript>
<Value name="1">
<Value>Valid</Value>
</Value>
<Value name="2">
<Value>IssueCount</Value>
</Value>
<Value name="3">
<Value>Issues</Value>
</Value>
<Value name="4">
<Value>Outcome</Value>
</Value>
<Value name="5">
<Value>FileName</Value>
</Value>
<Value name="6">
<Value>ControlId</Value>
</Value>
</Data>
<DefaultData>FHIRResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
