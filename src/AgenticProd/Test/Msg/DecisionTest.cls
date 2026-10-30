/// Unit tests for AgenticProd.Msg.Decision.FromAgentText. Stub agent text only, no LLM.
Class AgenticProd.Test.Msg.DecisionTest Extends AgenticProd.Test.Case
{

Method TestValidJSON()
{
	Set tText = "{""decision"":""AUTO_FIX"",""error_class"":""BAD_FORMAT"",""confidence"":0.92,"
		_"""fix"":[{""path"":""OBX(1):14"",""from"":""2026-10-23 10:15"",""to"":""202610231015""}],"
		_"""mapping"":{""local_code"":"""",""loinc"":"""",""display"":""""},"
		_"""validated"":true,""evidence"":[""validate_fix: pass""],""reason"":""TS had separators""}"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do $$$AssertStatusOK(tSC, "valid AUTO_FIX parses")
	Quit:'$IsObject(tDecision)
	Do $$$AssertEquals(tDecision.Decision, "AUTO_FIX")
	Do $$$AssertEquals(tDecision.ErrorClass, "BAD_FORMAT")
	Do $$$AssertEquals(tDecision.Confidence, .92)
	Do $$$AssertEquals(tDecision.Validated, 1)
	Do $$$AssertEquals(tDecision.Fix.Count(), 1)
	Do $$$AssertEquals(tDecision.Fix.GetAt(1).Path, "OBX(1):14")
	Do $$$AssertEquals(tDecision.Fix.GetAt(1).ToValue, "202610231015")
	Do $$$AssertEquals(tDecision.Evidence.GetAt(1), "validate_fix: pass")

	// MAP_CODE wrapped in a markdown fence, with an extra key the model invented.
	Set tText = "Here is my decision:"_$CHAR(10)_"```json"_$CHAR(10)
		_"{""decision"":""MAP_CODE"",""error_class"":""UNMAPPED_CODE"",""confidence"":0.81,""fix"":[],"
		_"""mapping"":{""local_code"":""GLU-01"",""loinc"":""2345-7"",""display"":""Glucose [Mass/volume] in Serum or Plasma""},"
		_"""validated"":false,""evidence"":[],""reason"":""Local glucose code"",""notes"":""extra""}"
		_$CHAR(10)_"```"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do $$$AssertStatusOK(tSC, "fenced MAP_CODE parses")
	Quit:'$IsObject(tDecision)
	Do $$$AssertEquals(tDecision.Mapping.LocalCode, "GLU-01")
	Do $$$AssertEquals(tDecision.Mapping.Loinc, "2345-7")
}

Method TestInvalidJSON()
{
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText("{""decision"":""ESCALATE"",""error_class"": }", .tDecision)
	Do ..AssertContractError(tSC, tDecision, "invalid JSON")

	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText("I could not decide.", .tDecision)
	Do ..AssertContractError(tSC, tDecision, "no JSON object found")
}

Method TestMissingField()
{
	Set tText = "{""decision"":""ESCALATE"",""confidence"":0.4,""validated"":false,""reason"":""unclear""}"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do ..AssertContractError(tSC, tDecision, "missing required field 'error_class'")
}

Method TestUnknownEnumValue()
{
	Set tText = "{""decision"":""FIX_IT"",""error_class"":""BAD_FORMAT"",""confidence"":0.9,""validated"":false,""reason"":""x""}"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do ..AssertContractError(tSC, tDecision, "unknown decision 'FIX_IT'")

	Set tText = "{""decision"":""ESCALATE"",""error_class"":""WEIRD"",""confidence"":0.9,""validated"":false,""reason"":""x""}"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do ..AssertContractError(tSC, tDecision, "unknown error_class 'WEIRD'")
}

Method TestIdentityIssueAutoFixRejected()
{
	Set tText = "{""decision"":""AUTO_FIX"",""error_class"":""IDENTITY_ISSUE"",""confidence"":0.99,"
		_"""fix"":[{""path"":""PID:3"",""from"":""123"",""to"":""123^^^HOSP^MR""}],"
		_"""validated"":true,""evidence"":[],""reason"":""add assigning authority""}"
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Do ..AssertContractError(tSC, tDecision, "IDENTITY_ISSUE can never be AUTO_FIX")
}

/// Assert a contract error whose text contains pExpected and that no Decision was returned.
Method AssertContractError(pSC As %Status, pDecision, pExpected As %String)
{
	Set tText = $SYSTEM.Status.GetErrorText(pSC)
	Do $$$AssertStatusNotOK(pSC, "rejected: "_tText)
	Do $$$AssertTrue(tText [ pExpected, "error mentions '"_pExpected_"'")
	Do $$$AssertEquals(pDecision, "", "no Decision returned")
}

}
