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
</Data>
<DataLocation>^AgenticProd.Data.PluginItemD</DataLocation>
<DefaultData>PluginItemDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.PluginItemD</IdLocation>
<IndexLocation>^AgenticProd.Data.PluginItemI</IndexLocation>
<StreamLocation>^AgenticProd.Data.PluginItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
