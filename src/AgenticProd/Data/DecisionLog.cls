/// Persistent copy of every Decision, linked by the TriageRequest header ID.
/// Message purge may delete Msg.Decision; history, get_similar_decisions, the dashboard and
/// evals read this table only.
Class AgenticProd.Data.DecisionLog Extends %Persistent
{

/// Ens.MessageHeader ID of the TriageRequest.
Property HeaderId As %Integer [ Required ];

Property SessionId As %Integer;

Property Source As %String(MAXLEN = 128);

Property Format As %String(MAXLEN = 20);

/// Interface error text, kept so get_similar_decisions can match on it after purge.
Property ErrorText As %String(MAXLEN = "");

Property Decision As AgenticProd.Msg.DecisionType [ Required ];

Property ErrorClass As AgenticProd.Msg.ErrorClass [ Required ];

Property Confidence As %Numeric(SCALE = 4);

/// The agent's claim, not proof; Triage re-runs validate_fix.
Property Validated As %Boolean;

Property LocalCode As %String(MAXLEN = 100);

Property Loinc As %String(MAXLEN = 20);

Property Reason As %String(MAXLEN = "");

/// Full decision as JSON (fix steps, mapping, evidence) so nothing depends on the message body.
Property DecisionJSON As %String(MAXLEN = "");

Property Model As %String(MAXLEN = 100);

Property AgentSessionId As %String(MAXLEN = 50);

Property CostUsd As %Numeric(SCALE = 6);

/// What actually happened, set later by Triage or the Workflow response (APPLIED, APPROVED, ...).
Property Outcome As %String(MAXLEN = 30);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

/// Body Triage built for an APPLIED fix. If that body fails again, Triage escalates without
/// calling the agent (loop guard).
Property FixedBodyClass As %String(MAXLEN = 128);

Property FixedBodyId As %String(MAXLEN = 50);

/// Workflow user who answered the ApprovalTask, and when (UTC).
Property Reviewer As %String(MAXLEN = 128);

Property ReviewedAt As %TimeStamp;

/// Why a reviewer-approved fix was not applied (re-check FAIL or REFUSED).
Property ReviewNote As %String(MAXLEN = "");

Index HeaderIdx On HeaderId;

Index FixedBodyIdx On (FixedBodyId, FixedBodyClass);

Index ErrorClassIdx On ErrorClass [ Type = bitmap ];

Index LocalCodeIdx On LocalCode;

/// Copy a Decision and the request it answers into the log. pOutcome is what Triage did;
/// pFixedBody is the new message of an APPLIED fix.
ClassMethod Record(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pId As %String, pOutcome As %String = "", pFixedBody As %Persistent = "") As %Status
{
	Set pId = ""
	Set tSC = $$$OK
	Try {
		Set tRow = ..%New()
		Set tRow.HeaderId = pRequest.HeaderId
		Set tRow.SessionId = pRequest.SessionId
		Set tRow.Source = pRequest.Source
		Set tRow.Format = pRequest.Format
		Set tRow.ErrorText = pRequest.ErrorText
		Set tRow.Decision = pDecision.Decision
		Set tRow.ErrorClass = pDecision.ErrorClass
		Set tRow.Confidence = pDecision.Confidence
		Set tRow.Validated = pDecision.Validated
		If $IsObject(pDecision.Mapping) {
			Set tRow.LocalCode = pDecision.Mapping.LocalCode
			Set tRow.Loinc = pDecision.Mapping.Loinc
		}
		Set tRow.Reason = pDecision.Reason
		Set tRow.Model = pDecision.Model
		Set tRow.AgentSessionId = pDecision.AgentSessionId
		Set tRow.CostUsd = pDecision.CostUsd
		Set tRow.Outcome = pOutcome
		If $IsObject(pFixedBody) {
			Set tRow.FixedBodyClass = $CLASSNAME(pFixedBody)
			Set tRow.FixedBodyId = pFixedBody.%Id()
		}
		$$$ThrowOnError(pDecision.%JSONExportToString(.tJSON))
		Set tRow.DecisionJSON = tJSON
		$$$ThrowOnError(tRow.%Save())
		Set pId = tRow.%Id()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Storage Default
{
<Data name="DecisionLogDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>HeaderId</Value>
</Value>
<Value name="3">
<Value>SessionId</Value>
</Value>
<Value name="4">
<Value>Source</Value>
</Value>
<Value name="5">
<Value>Format</Value>
</Value>
<Value name="6">
<Value>ErrorText</Value>
</Value>
<Value name="7">
<Value>Decision</Value>
</Value>
<Value name="8">
<Value>ErrorClass</Value>
</Value>
<Value name="9">
<Value>Confidence</Value>
</Value>
<Value name="10">
<Value>Validated</Value>
</Value>
<Value name="11">
<Value>LocalCode</Value>
</Value>
<Value name="12">
<Value>Loinc</Value>
</Value>
<Value name="13">
<Value>Reason</Value>
</Value>
<Value name="14">
<Value>DecisionJSON</Value>
</Value>
<Value name="15">
<Value>Model</Value>
</Value>
<Value name="16">
<Value>AgentSessionId</Value>
</Value>
<Value name="17">
<Value>CostUsd</Value>
</Value>
<Value name="18">
<Value>Outcome</Value>
</Value>
<Value name="19">
<Value>CreatedAt</Value>
</Value>
<Value name="20">
<Value>FixedBodyClass</Value>
</Value>
<Value name="21">
<Value>FixedBodyId</Value>
</Value>
<Value name="22">
<Value>Reviewer</Value>
</Value>
<Value name="23">
<Value>ReviewedAt</Value>
</Value>
<Value name="24">
<Value>ReviewNote</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.DecisionLogD</DataLocation>
<DefaultData>DecisionLogDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.DecisionLogD</IdLocation>
<IndexLocation>^AgenticProd.Data.DecisionLogI</IndexLocation>
<StreamLocation>^AgenticProd.Data.DecisionLogS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
