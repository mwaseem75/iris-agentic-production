/// One production item the plug-in installer added to another production. Disable removes
/// exactly these rows' items, so nothing the customer configured is touched. Shared with every
/// plug-in namespace (Data.* mapping), so IRISAPP sees what is installed where.
Class AgenticProd.Data.PluginItem Extends %Persistent
{

Property Namespace As %String(MAXLEN = 64) [ Required ];

Property Production As %String(MAXLEN = 128) [ Required ];

/// Config name of the added item.
Property ItemName As %String(MAXLEN = 128) [ Required ];

Property ClassName As %String(MAXLEN = 128);

/// observe or act, as installed.
Property Mode As %String(MAXLEN = 20);

Property AddedBy As %String(MAXLEN = 128) [ InitialExpression = {$USERNAME} ];

Property AddedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

/// Name of the agent host item of an "Add to production" install; its items share this owner and
/// Remove takes out exactly them. Empty for the AI.* plug-in, which Disable removes as one set.
Property Owner As %String(MAXLEN = 128);

/// Agent class the install hosts (MyAI.Agent.X); set on the owner's host item row.
Property AgentClass As %String(MAXLEN = 128);

Index OwnerIdx On Owner;

Index ItemIdx On (Namespace, Production, ItemName) [ Unique ];

Storage Default
{
<Data name="PluginItemDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Namespace</Value>
</Value>
<Value name="3">
<Value>Production</Value>
</Value>
<Value name="4">
<Value>ItemName</Value>
</Value>
<Value name="5">
<Value>ClassName</Value>
</Value>
<Value name="6">
<Value>Mode</Value>
</Value>
<Value name="7">
<Value>AddedBy</Value>
</Value>
<Value name="8">
<Value>AddedAt</Value>
</Value>
<Value name="9">
<Value>Owner</Value>
</Value>
<Value name="10">
<Value>AgentClass</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.PluginItemD</DataLocation>
<DefaultData>PluginItemDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.PluginItemD</IdLocation>
<IndexLocation>^AgenticProd.Data.PluginItemI</IndexLocation>
<StreamLocation>^AgenticProd.Data.PluginItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
