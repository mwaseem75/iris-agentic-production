/// One row per changed setting, written by Settings.Store. API keys never appear here: their
/// old and new values are logged as "changed". Never purged.
Class AgenticProd.Data.SettingsAudit Extends %Persistent
{

Property ChangedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

/// IRIS user who made the change ($USERNAME of the REST request).
Property ChangedBy As %String(MAXLEN = 128);

/// providers, keys, agents, budgets, prices or test (test connection, not a change).
/// Not "Section": a reserved word in IRIS SQL.
Property Scope As %String(MAXLEN = 20);

/// Provider config name, production item or price model.
Property Item As %String(MAXLEN = 200);

Property Field As %String(MAXLEN = 100);

Property OldValue As %String(MAXLEN = 1000);

Property NewValue As %String(MAXLEN = 1000);

Index ChangedAtIdx On ChangedAt;

/// Write one row. pOld and pNew are stored as given; callers mask secrets before.
ClassMethod Log(pScope As %String, pItem As %String, pField As %String, pOld As %String, pNew As %String) As %Status
{
	Set tRow = ..%New()
	Set tRow.ChangedBy = $USERNAME
	Set tRow.Scope = pScope
	Set tRow.Item = pItem
	Set tRow.Field = pField
	Set tRow.OldValue = $EXTRACT(pOld, 1, 1000)
	Set tRow.NewValue = $EXTRACT(pNew, 1, 1000)
	Quit tRow.%Save()
}

Storage Default
{
<Data name="SettingsAuditDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ChangedAt</Value>
</Value>
<Value name="3">
<Value>ChangedBy</Value>
</Value>
<Value name="4">
<Value>Scope</Value>
</Value>
<Value name="5">
<Value>Item</Value>
</Value>
<Value name="6">
<Value>Field</Value>
</Value>
<Value name="7">
<Value>OldValue</Value>
</Value>
<Value name="8">
<Value>NewValue</Value>
</Value>
</Data>
<DataLocation>^AgenticProd8110.SettingsAuditD</DataLocation>
<DefaultData>SettingsAuditDefaultData</DefaultData>
<IdLocation>^AgenticProd8110.SettingsAuditD</IdLocation>
<IndexLocation>^AgenticProd8110.SettingsAuditI</IndexLocation>
<StreamLocation>^AgenticProd8110.SettingsAuditS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
