/// One agent tool call, allowed or denied. Written by Policy.Audit; never purged.
/// Arguments are stored as the model sent them, so tools must not accept unmasked PHI.
Class AgenticProd.Data.ToolCall Extends %Persistent
{

Property HeaderId As %Integer;

/// Namespace the row's header and session IDs belong to: they are only unique within it
/// (IRISAPP, or a plug-in namespace such as LEGACY that shares this table).
Property Namespace As %String(MAXLEN = 64) [ InitialExpression = {$NAMESPACE} ];

Property AgentSessionId As %String(MAXLEN = 50);

Property Tool As %String(MAXLEN = 200) [ Required ];

/// JSON text of the call arguments.
Property Arguments As %String(MAXLEN = "");

Property Status As %String(DISPLAYLIST = ",OK,Error,Denied", VALUELIST = ",OK,ERROR,DENIED") [ Required ];

Property ErrorText As %String(MAXLEN = 2000);

Property DurationMs As %Integer;

/// Length of the tool result text; the result itself stays in the AI Hub session.
Property ResultLength As %Integer;

/// validate_fix only: the verdict it returned (PASS, PASS_NEEDS_REVIEW, FAIL, REFUSED).
Property Verdict As %String(MAXLEN = 30);

/// search_loinc only: the LOINC codes it returned, comma separated, for the grounding gate.
Property ResultSummary As %String(MAXLEN = 2000);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Index HeaderIdx On HeaderId;

Index SessionIdx On AgentSessionId;

Index ToolIdx On Tool [ Type = bitmap ];

/// Save one call. pArgs may be a %DynamicObject or JSON text.
ClassMethod Log(pTool As %String, pArgs, pStatus As %String, pDurationMs As %Integer = "", pResultLength As %Integer = "", pErrorText As %String = "", pHeaderId As %Integer = "", pAgentSessionId As %String = "", Output pId As %String, pVerdict As %String = "", pResultSummary As %String = "") As %Status
{
	Set pId = ""
	Set tSC = $$$OK
	Try {
		Set tRow = ..%New()
		Set tRow.Tool = pTool
		Set tRow.Arguments = $SELECT($IsObject(pArgs):pArgs.%ToJSON(), 1:pArgs)
		Set tRow.Status = pStatus
		Set tRow.DurationMs = pDurationMs
		Set tRow.ResultLength = pResultLength
		Set tRow.ErrorText = $EXTRACT(pErrorText, 1, 2000)
		Set tRow.HeaderId = pHeaderId
		Set tRow.AgentSessionId = pAgentSessionId
		Set tRow.Verdict = pVerdict
		Set tRow.ResultSummary = $EXTRACT(pResultSummary, 1, 2000)
		$$$ThrowOnError(tRow.%Save())
		Set pId = tRow.%Id()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Verdict in a validate_fix result text (Tools.HL7.ValidateFix wraps the JSON in an
/// untrusted_data block, and the session may hold it JSON-escaped); "" when there is none.
ClassMethod VerdictOf(pResult As %String) As %String
{
	Set tMatch = ##class(%Regex.Matcher).%New("""result\\?""\s*:\s*\\?""(PASS_NEEDS_REVIEW|PASS|FAIL|REFUSED)", pResult)
	Quit $SELECT(tMatch.Locate(): tMatch.Group(1), 1: "")
}

/// LOINC codes in a search_loinc result text, comma separated, in result order; "" when none.
/// The result may be JSON-escaped like a validate_fix one.
ClassMethod LoincCodesOf(pResult As %String) As %String
{
	Set tCodes = ""
	Set tMatch = ##class(%Regex.Matcher).%New("""loinc\\?""\s*:\s*\\?""(\d{1,7}-\d)", pResult)
	While tMatch.Locate() {
		Set:'$LISTFIND($LISTFROMSTRING(tCodes), tMatch.Group(1)) tCodes = tCodes_$SELECT(tCodes '= "": ",", 1: "")_tMatch.Group(1)
	}
	Quit tCodes
}

/// Fill Verdict on validate_fix rows logged before it was recorded, from the saved AI Hub
/// session: the n-th validate_fix result in the session belongs to the n-th row. pFilled = rows set.
ClassMethod BackfillVerdicts(Output pFilled As %Integer) As %Status
{
	Set tSC = $$$OK, pFilled = 0
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT AgentSessionId FROM AgenticProd_Data.ToolCall WHERE Tool = 'validate_fix' AND Verdict IS NULL AND Status = 'OK' AND AgentSessionId IS NOT NULL AND Namespace = ?", $NAMESPACE)
		While tRS.%Next() {
			Set tSession = ##class(%AI.Agent.Session).%OpenId(tRS.AgentSessionId)
			Continue:'$IsObject(tSession)
			Kill tVerdicts
			Do ..SessionVerdicts(tSession, .tVerdicts)
			Set tRows = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? AND Tool = 'validate_fix' AND Status = 'OK' ORDER BY ID", tRS.AgentSessionId, $NAMESPACE), tN = 0
			While tRows.%Next() {
				Set tN = tN + 1
				Continue:$GET(tVerdicts(tN))=""
				Set tRow = ..%OpenId(tRows.ID)
				Continue:tRow.Verdict'=""
				Set tRow.Verdict = tVerdicts(tN)
				$$$ThrowOnError(tRow.%Save())
				Set pFilled = pFilled + 1
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// pVerdicts(n) = verdict of the n-th validate_fix call in pSession, matched by tool_call_id.
ClassMethod SessionVerdicts(pSession As %AI.Agent.Session, Output pVerdicts) [ Internal ]
{
	Kill pVerdicts
	Set tStream = pSession.ContextData
	Quit:'$IsObject(tStream)
	Do tStream.Rewind()
	Set tContext = ##class(%DynamicObject).%FromJSON(tStream)
	Quit:'$IsObject(tContext.messages)
	Set tN = 0, tIter = tContext.messages.%GetIterator()
	While tIter.%GetNext(, .tMsg) {
		If $IsObject(tMsg."tool_calls") {
			Set tCalls = tMsg."tool_calls".%GetIterator()
			While tCalls.%GetNext(, .tCall) {
				If tCall.name = "validate_fix" Set tN = tN + 1, tCallN(tCall.id) = tN
			}
		} ElseIf tMsg.role = "tool" {
			Set tId = tMsg."tool_call_id"
			Set:(tId'="")&&$DATA(tCallN(tId)) pVerdicts(tCallN(tId)) = ..VerdictOf(tMsg.content)
		}
	}
}

Storage Default
{
<Data name="ToolCallDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>HeaderId</Value>
</Value>
<Value name="3">
<Value>AgentSessionId</Value>
</Value>
<Value name="4">
<Value>Tool</Value>
</Value>
<Value name="5">
<Value>Arguments</Value>
</Value>
<Value name="6">
<Value>Status</Value>
</Value>
<Value name="7">
<Value>ErrorText</Value>
</Value>
<Value name="8">
<Value>DurationMs</Value>
</Value>
<Value name="9">
<Value>ResultLength</Value>
</Value>
<Value name="10">
<Value>CreatedAt</Value>
</Value>
<Value name="11">
<Value>Verdict</Value>
</Value>
<Value name="12">
<Value>ResultSummary</Value>
</Value>
<Value name="13">
<Value>Namespace</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.ToolCallD</DataLocation>
<DefaultData>ToolCallDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.ToolCallD</IdLocation>
<IndexLocation>^AgenticProd.Data.ToolCallI</IndexLocation>
<StreamLocation>^AgenticProd.Data.ToolCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
