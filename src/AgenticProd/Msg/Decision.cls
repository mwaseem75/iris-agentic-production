/// The agent's decision for one failed message (see the decision contract in CLAUDE.md).
/// Build it from the agent's text with <method>FromAgentText</method>; never trust the text directly.
Class AgenticProd.Msg.Decision Extends (Ens.Response, %JSON.Adaptor)
{

/// Extra keys from the model are ignored; required keys and enum values are checked in Validate().
Parameter %JSONIGNOREINVALIDFIELD = 1;

Property Decision As AgenticProd.Msg.DecisionType(%JSONFIELDNAME = "decision") [ Required ];

Property ErrorClass As AgenticProd.Msg.ErrorClass(%JSONFIELDNAME = "error_class") [ Required ];

/// Self-reported confidence, 0 to 1.
Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", MAXVAL = 1, MINVAL = 0, SCALE = 4) [ Required ];

/// Proposed changes for AUTO_FIX.
Property Fix As list Of AgenticProd.Msg.FixStep(%JSONFIELDNAME = "fix");

/// Proposed code mapping for MAP_CODE.
Property Mapping As AgenticProd.Msg.CodeMapping(%JSONFIELDNAME = "mapping");

/// The agent's claim that validate_fix passed. Triage re-checks it; this is not proof.
Property Validated As %Boolean(%JSONFIELDNAME = "validated") [ InitialExpression = 0 ];

Property Evidence As list Of %String(%JSONFIELDNAME = "evidence", MAXLEN = 1000);

Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = "");

/// Set by the agent operation, never read from the model's JSON.
Property Model As %String(%JSONINCLUDE = "OUTPUTONLY", MAXLEN = 100);

Property PromptTokens As %Integer(%JSONINCLUDE = "OUTPUTONLY");

Property CompletionTokens As %Integer(%JSONINCLUDE = "OUTPUTONLY");

Property CostUsd As %Numeric(%JSONINCLUDE = "OUTPUTONLY", SCALE = 6);

/// ID of the saved %AI.Agent.Session that produced this decision (for replay).
Property AgentSessionId As %String(%JSONINCLUDE = "OUTPUTONLY", MAXLEN = 50);

/// Parse the agent's final text into a Decision.
/// Accepts the JSON object alone or wrapped in prose or a ```json fence.
/// On failure pDecision is "" and the status says what is wrong (bad JSON, missing field,
/// unknown decision or error_class, forbidden combination), so the caller can send it back
/// to the agent for its one retry.
ClassMethod FromAgentText(pText As %String, Output pDecision As AgenticProd.Msg.Decision) As %Status
{
	Set pDecision = ""
	Set tSC = $$$OK
	Try {
		Set tJSON = ..ExtractJSON(pText)
		If tJSON = "" {
			Set tSC = ..ContractError("no JSON object found in the agent response")
			Quit
		}
		Try {
			Set tObj = ##class(%DynamicAbstractObject).%FromJSON(tJSON)
		} Catch exJSON {
			Set tSC = ..ContractError("invalid JSON: "_exJSON.DisplayString())
		}
		Quit:$$$ISERR(tSC)

		Set tSC = ..Validate(tObj)
		Quit:$$$ISERR(tSC)

		Set tDecision = ..%New()
		Set tSC = tDecision.%JSONImport(tObj)
		If $$$ISOK(tSC) Set tSC = tDecision.%ValidateObject()
		If $$$ISERR(tSC) {
			Set tSC = ..ContractError("does not match the schema: "_$SYSTEM.Status.GetErrorText(tSC))
			Quit
		}
		Set pDecision = tDecision
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Check required fields, types, enum values and the contract's hard rules.
/// Removes null optional fields so %JSONImport does not trip on them.
ClassMethod Validate(pObj As %DynamicObject) As %Status
{
	For tField = "decision","error_class","confidence","validated","reason" {
		If $LISTFIND($LISTBUILD("unassigned","null"), pObj.%GetTypeOf(tField)) {
			Return ..ContractError("missing required field '"_tField_"'")
		}
	}

	Set tDecision = pObj.decision
	If (pObj.%GetTypeOf("decision") '= "string") || $$$ISERR(##class(AgenticProd.Msg.DecisionType).IsValid(tDecision)) {
		Return ..ContractError("unknown decision '"_tDecision_"' (allowed: "_..Allowed(##class(AgenticProd.Msg.DecisionType).#VALUELIST)_")")
	}
	Set tErrorClass = pObj."error_class"
	If (pObj.%GetTypeOf("error_class") '= "string") || $$$ISERR(##class(AgenticProd.Msg.ErrorClass).IsValid(tErrorClass)) {
		Return ..ContractError("unknown error_class '"_tErrorClass_"' (allowed: "_..Allowed(##class(AgenticProd.Msg.ErrorClass).#VALUELIST)_")")
	}

	If (pObj.%GetTypeOf("confidence") '= "number") || (pObj.confidence < 0) || (pObj.confidence > 1) {
		Return ..ContractError("confidence must be a number from 0 to 1")
	}
	If (pObj.%GetTypeOf("validated") '= "boolean") {
		Return ..ContractError("validated must be true or false")
	}
	If (pObj.%GetTypeOf("reason") '= "string") {
		Return ..ContractError("reason must be a string")
	}

	For tField = "fix","mapping","evidence" {
		Do:pObj.%GetTypeOf(tField)="null" pObj.%Remove(tField)
	}
	If pObj.%IsDefined("fix") {
		If pObj.%GetTypeOf("fix") '= "array" Return ..ContractError("fix must be an array")
		Set tIter = pObj.fix.%GetIterator()
		While tIter.%GetNext(.tKey, .tStep) {
			If '$IsObject(tStep) || 'tStep.%IsA("%DynamicObject") || (tStep.%GetTypeOf("path") '= "string") || (tStep.path = "") {
				Return ..ContractError("fix["_tKey_"] must be an object with a non-empty 'path'")
			}
		}
	}
	If pObj.%IsDefined("mapping") && (pObj.%GetTypeOf("mapping") '= "object") {
		Return ..ContractError("mapping must be an object")
	}
	If pObj.%IsDefined("evidence") {
		If pObj.%GetTypeOf("evidence") '= "array" Return ..ContractError("evidence must be an array of strings")
		Set tIter = pObj.evidence.%GetIterator()
		While tIter.%GetNext(.tKey, .tItem) {
			If pObj.evidence.%GetTypeOf(tKey) '= "string" Return ..ContractError("evidence["_tKey_"] must be a string")
		}
	}

	// Hard rules from the contract.
	If (tErrorClass = "IDENTITY_ISSUE") && (tDecision = "AUTO_FIX") {
		Return ..ContractError("IDENTITY_ISSUE can never be AUTO_FIX; use ESCALATE")
	}
	If (tDecision = "AUTO_FIX") && ('pObj.%IsDefined("fix") || (pObj.fix.%Size() = 0)) {
		Return ..ContractError("AUTO_FIX needs at least one fix step")
	}
	If (tDecision = "MAP_CODE") && ('pObj.%IsDefined("mapping") || (pObj.mapping."local_code" = "") || (pObj.mapping.loinc = "")) {
		Return ..ContractError("MAP_CODE needs mapping.local_code and mapping.loinc")
	}
	Quit $$$OK
}

/// Copy of this decision turned into ESCALATE with pReason. Fix, mapping and evidence stay so
/// the reviewer sees the proposal; Validated is cleared since the proposal is no longer trusted.
Method Escalated(pReason As %String) As AgenticProd.Msg.Decision
{
	Set tCopy = ..%ConstructClone(1)
	Set tCopy.Decision = "ESCALATE"
	Set tCopy.Validated = 0
	Set tCopy.Reason = pReason
	Quit tCopy
}

/// Text from the first "{" to the last "}", or "" if there is none.
ClassMethod ExtractJSON(pText As %String) As %String [ Internal ]
{
	Set tStart = $FIND(pText, "{") - 1
	Set tPieces = $LENGTH(pText, "}")
	Quit:(tStart < 1)||(tPieces < 2) ""
	Set tEnd = $LENGTH($PIECE(pText, "}", 1, tPieces - 1)) + 1
	Quit:tEnd<tStart ""
	Quit $EXTRACT(pText, tStart, tEnd)
}

ClassMethod Allowed(pValueList As %String) As %String [ Internal ]
{
	Quit $TRANSLATE($EXTRACT(pValueList, 2, *), ",", "|")
}

ClassMethod ContractError(pText As %String) As %Status [ Internal ]
{
	Quit $$$ERROR($$$GeneralError, "Decision contract: "_pText)
}

Storage Default
{
<Data name="DecisionDefaultData">
<Subscript>"Decision"</Subscript>
<Value name="1">
<Value>Decision</Value>
</Value>
<Value name="2">
<Value>ErrorClass</Value>
</Value>
<Value name="3">
<Value>Confidence</Value>
</Value>
<Value name="4">
<Value>Fix</Value>
</Value>
<Value name="5">
<Value>Mapping</Value>
</Value>
<Value name="6">
<Value>Validated</Value>
</Value>
<Value name="7">
<Value>Evidence</Value>
</Value>
<Value name="8">
<Value>Reason</Value>
</Value>
<Value name="9">
<Value>Model</Value>
</Value>
<Value name="10">
<Value>PromptTokens</Value>
</Value>
<Value name="11">
<Value>CompletionTokens</Value>
</Value>
<Value name="12">
<Value>CostUsd</Value>
</Value>
<Value name="13">
<Value>AgentSessionId</Value>
</Value>
</Data>
<DefaultData>DecisionDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
