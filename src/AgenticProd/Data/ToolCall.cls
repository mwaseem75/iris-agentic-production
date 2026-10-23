/// One agent tool call, allowed or denied. Written by Policy.Audit; never purged.
/// Arguments are stored as the model sent them, so tools must not accept unmasked PHI.
Class AgenticProd.Data.ToolCall Extends %Persistent
{

Property HeaderId As %Integer;

Property AgentSessionId As %String(MAXLEN = 50);

Property Tool As %String(MAXLEN = 200) [ Required ];

/// JSON text of the call arguments.
Property Arguments As %String(MAXLEN = "");

Property Status As %String(DISPLAYLIST = ",OK,Error,Denied", VALUELIST = ",OK,ERROR,DENIED") [ Required ];

Property ErrorText As %String(MAXLEN = 2000);

Property DurationMs As %Integer;

/// Length of the tool result text; the result itself stays in the AI Hub session.
Property ResultLength As %Integer;

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Index HeaderIdx On HeaderId;

Index SessionIdx On AgentSessionId;

Index ToolIdx On Tool [ Type = bitmap ];

/// Save one call. pArgs may be a %DynamicObject or JSON text.
ClassMethod Log(pTool As %String, pArgs, pStatus As %String, pDurationMs As %Integer = "", pResultLength As %Integer = "", pErrorText As %String = "", pHeaderId As %Integer = "", pAgentSessionId As %String = "", Output pId As %String) As %Status
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
		$$$ThrowOnError(tRow.%Save())
		Set pId = tRow.%Id()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
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
</Data>
<DataLocation>^AgenticProd.Data.ToolCallD</DataLocation>
<DefaultData>ToolCallDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.ToolCallD</IdLocation>
<IndexLocation>^AgenticProd.Data.ToolCallI</IndexLocation>
<StreamLocation>^AgenticProd.Data.ToolCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
