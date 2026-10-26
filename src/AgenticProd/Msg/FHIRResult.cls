/// What Operation.NphiesFHIROut did with one HL7 result: valid bundles are written, invalid ones
/// are not, and LabRouter sends them to Triage with Format FHIR.
Class AgenticProd.Msg.FHIRResult Extends Ens.Response
{

Property Valid As %Boolean;

/// Error and fatal issues only; warnings and information do not make a bundle invalid.
Property IssueCount As %Integer;

/// One line per issue, "Observation[1] Observation.valueQuantity.value: ...", for the TriageRequest.
Property Issues As %String(MAXLEN = "");

/// OperationOutcome JSON with the error issues, expressions prefixed with the bundle entry.
Property Outcome As %Stream.GlobalCharacter;

/// File written to the simulated NPHIES FHIR endpoint; empty when invalid.
Property FileName As %String(MAXLEN = 500);

}
