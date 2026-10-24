/// Workflow task asking a person to approve or reject a MAP_CODE or ESCALATE decision.
/// The reviewer can correct the LOINC in the Loinc form field; Triage reads it back from
/// the TaskResponse %FormValues.
Class AgenticProd.Msg.ApprovalTask Extends EnsLib.Workflow.TaskRequest
{

/// Ens.MessageHeader ID of the failed message.
Property HeaderId As %Integer;

Property Decision As AgenticProd.Msg.DecisionType;

Property ErrorClass As AgenticProd.Msg.ErrorClass;

Property LocalCode As %String(MAXLEN = 100);

Property Loinc As %String(MAXLEN = 20);

Property Display As %String(MAXLEN = 500);

/// Proposed fix steps as a JSON array of {"path","from","to"} (the CheckFix input).
Property FixJSON As %String(MAXLEN = "");

Property Confidence As %Numeric(SCALE = 4);

Property Evidence As list Of %String(MAXLEN = 1000);

Property Reason As %String(MAXLEN = "");

/// InjectionGuard hits from the TriageRequest.
Property Flags As list Of %String(MAXLEN = 500);

/// Task for pDecision on the message in pRequest.
ClassMethod FromDecision(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision) As AgenticProd.Msg.ApprovalTask
{
	Set tTask = ..%New()
	Set tTask.HeaderId = pRequest.HeaderId
	Set tTask.Decision = pDecision.Decision
	Set tTask.ErrorClass = pDecision.ErrorClass
	Set tTask.Confidence = pDecision.Confidence
	Set tTask.Reason = pDecision.Reason
	If $IsObject(pDecision.Mapping) {
		Set tTask.LocalCode = pDecision.Mapping.LocalCode
		Set tTask.Loinc = pDecision.Mapping.Loinc
		Set tTask.Display = pDecision.Mapping.Display
	}
	If pDecision.Fix.Count() {
		Set tFix = []
		For i = 1:1:pDecision.Fix.Count() {
			Set tStep = pDecision.Fix.GetAt(i)
			Do tFix.%Push({"path":(tStep.Path), "from":(tStep.FromValue), "to":(tStep.ToValue)})
		}
		Set tTask.FixJSON = tFix.%ToJSON()
	}
	For i = 1:1:pDecision.Evidence.Count() Do tTask.Evidence.Insert(pDecision.Evidence.GetAt(i))
	For i = 1:1:pRequest.Flags.Count() Do tTask.Flags.Insert(pRequest.Flags.GetAt(i))

	Set tTask.%Actions = "Approve,Reject"
	Set tTask.%FormFields = "Loinc"
	Do tTask.%FormValues.SetAt(tTask.Loinc, "Loinc")
	Set tTask.%Subject = pDecision.Decision_" "_pDecision.ErrorClass_" for message header "_pRequest.HeaderId
	Set tNL = $CHAR(13,10)
	Set tText = "Error: "_pRequest.ErrorText_tNL_"Agent confidence: "_pDecision.Confidence_tNL_"Reason: "_pDecision.Reason
	If tTask.LocalCode '= "" Set tText = tText_tNL_"Mapping: "_tTask.LocalCode_" -> "_tTask.Loinc_" "_tTask.Display_" (correct the Loinc field if needed)"
	If tTask.FixJSON '= "" Set tText = tText_tNL_"Proposed fix: "_tTask.FixJSON
	For i = 1:1:tTask.Evidence.Count() Set tText = tText_tNL_"Evidence: "_tTask.Evidence.GetAt(i)
	Set tTask.%Message = tText
	Quit tTask
}

Storage Default
{
<Data name="ApprovalTaskDefaultData">
<Subscript>"ApprovalTask"</Subscript>
<Value name="1">
<Value>HeaderId</Value>
</Value>
<Value name="2">
<Value>Decision</Value>
</Value>
<Value name="3">
<Value>ErrorClass</Value>
</Value>
<Value name="4">
<Value>LocalCode</Value>
</Value>
<Value name="5">
<Value>Loinc</Value>
</Value>
<Value name="6">
<Value>Display</Value>
</Value>
<Value name="7">
<Value>FixJSON</Value>
</Value>
<Value name="8">
<Value>Confidence</Value>
</Value>
<Value name="9">
<Value>Evidence</Value>
</Value>
<Value name="10">
<Value>Reason</Value>
</Value>
<Value name="11">
<Value>Flags</Value>
</Value>
</Data>
<DefaultData>ApprovalTaskDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
