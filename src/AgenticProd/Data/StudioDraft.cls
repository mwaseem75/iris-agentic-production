/// AI Studio draft: the blocks someone is adding to a production, kept until they apply or
/// discard them. One row per namespace and production; the last save wins.
Class AgenticProd.Data.StudioDraft Extends %Persistent
{

Property Namespace As %String(MAXLEN = 64) [ Required ];

Property Production As %String(MAXLEN = 128) [ Required ];

/// Draft document as the page builds it (JSON text).
Property Json As %String(MAXLEN = "");

Property SavedBy As %String(MAXLEN = 128);

Property SavedAt As %TimeStamp;

Index ProdIdx On (Namespace, Production) [ Unique ];

/// Row for pNamespace/pProduction, or "".
ClassMethod Find(pNamespace As %String, pProduction As %String) As AgenticProd.Data.StudioDraft
{
	Quit:'..ProdIdxExists(pNamespace, pProduction, .tId) ""
	Quit ..%OpenId(tId)
}

/// Create or replace the draft. SavedBy is the IRIS user of the request.
ClassMethod Put(pNamespace As %String, pProduction As %String, pJson As %String) As %Status
{
	Set tRow = ..Find(pNamespace, pProduction)
	Set:tRow="" tRow = ..%New(), tRow.Namespace = pNamespace, tRow.Production = pProduction
	Set tRow.Json = pJson, tRow.SavedBy = $USERNAME, tRow.SavedAt = $ZDATETIME($ZTIMESTAMP, 3)
	Quit tRow.%Save()
}

Storage Default
{
<Data name="StudioDraftDefaultData">
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
<Value>Json</Value>
</Value>
<Value name="5">
<Value>SavedBy</Value>
</Value>
<Value name="6">
<Value>SavedAt</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.StudioDraftD</DataLocation>
<DefaultData>StudioDraftDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.StudioDraftD</IdLocation>
<IndexLocation>^AgenticProd.Data.StudioDraftI</IndexLocation>
<StreamLocation>^AgenticProd.Data.StudioDraftS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
