/// Token rates per model, in USD per 1M tokens. Edit rows in SQL or the portal when list prices
/// change; cost is never hardcoded. <method>Seed</method> only adds missing models.
Class AgenticProd.Data.PriceTable Extends %Persistent
{

Property Provider As %String(MAXLEN = 50) [ Required ];

/// Model ID as passed to the agent (Operation.Agent setting Model).
Property Model As %String(MAXLEN = 100) [ Required ];

Property InputPer1M As %Numeric(MINVAL = 0, SCALE = 6) [ Required ];

Property OutputPer1M As %Numeric(MINVAL = 0, SCALE = 6) [ Required ];

/// Rate for prompt tokens served from the provider cache.
Property CacheReadPer1M As %Numeric(MINVAL = 0, SCALE = 6);

/// Rate for tokens written to the cache (Anthropic bills these; OpenAI does not).
Property CacheWritePer1M As %Numeric(MINVAL = 0, SCALE = 6);

/// 1 = the provider counts cache reads inside prompt_tokens (OpenAI), so they are subtracted
/// before charging the input rate. 0 = cache tokens are reported separately (Anthropic).
Property PromptIncludesCache As %Boolean [ InitialExpression = 1 ];

/// Where the rate came from and when it was checked.
Property Note As %String(MAXLEN = 500);

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Index ModelIdx On Model [ Unique ];

/// Add the default rows for models we run. Existing rows are left alone so manual edits stick.
ClassMethod Seed() As %Status
{
	Set tSC = $$$OK
	Try {
		// OpenAI list prices, standard tier; recheck before quoting costs in the article.
		$$$ThrowOnError(..AddIfMissing("openai", "gpt-5-nano", .05, .40, .005, 0, 1, "OpenAI list price, checked 2026-10-24"))
		$$$ThrowOnError(..AddIfMissing("openai", "gpt-4o-mini", .15, .60, .075, 0, 1, "OpenAI list price, checked 2026-10-24"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod AddIfMissing(pProvider As %String, pModel As %String, pIn As %Numeric, pOut As %Numeric, pCacheRead As %Numeric, pCacheWrite As %Numeric, pPromptIncludesCache As %Boolean, pNote As %String) As %Status
{
	Quit:..ModelIdxExists(pModel) $$$OK
	Set tRow = ..%New()
	Set tRow.Provider = pProvider
	Set tRow.Model = pModel
	Set tRow.InputPer1M = pIn
	Set tRow.OutputPer1M = pOut
	Set tRow.CacheReadPer1M = pCacheRead
	Set tRow.CacheWritePer1M = pCacheWrite
	Set tRow.PromptIncludesCache = pPromptIncludesCache
	Set tRow.Note = pNote
	Quit tRow.%Save()
}

/// Cost in USD for one run. Reasoning tokens are not passed: providers already count them in
/// completion tokens. Returns an error if the model has no price row, so a missing rate is
/// noticed instead of recorded as zero.
ClassMethod Cost(pModel As %String, pPrompt As %Integer, pCompletion As %Integer, pCacheRead As %Integer = 0, pCacheWrite As %Integer = 0, Output pCost As %Numeric) As %Status
{
	Set pCost = ""
	Set tRow = ..ModelIdxOpen(pModel, , .tSC)
	If '$IsObject(tRow) Quit $$$ERROR($$$GeneralError, "No price row for model '"_pModel_"' in AgenticProd_Data.PriceTable")
	Set tInput = pPrompt
	Set:tRow.PromptIncludesCache tInput = pPrompt - pCacheRead - pCacheWrite
	Set:tInput<0 tInput = 0
	Set pCost = $NORMALIZE(((tInput * tRow.InputPer1M) + (pCompletion * tRow.OutputPer1M)
		+ (pCacheRead * +tRow.CacheReadPer1M) + (pCacheWrite * +tRow.CacheWritePer1M)) / 1000000, 6)
	Quit $$$OK
}

Storage Default
{
<Data name="PriceTableDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Provider</Value>
</Value>
<Value name="3">
<Value>Model</Value>
</Value>
<Value name="4">
<Value>InputPer1M</Value>
</Value>
<Value name="5">
<Value>OutputPer1M</Value>
</Value>
<Value name="6">
<Value>CacheReadPer1M</Value>
</Value>
<Value name="7">
<Value>CacheWritePer1M</Value>
</Value>
<Value name="8">
<Value>PromptIncludesCache</Value>
</Value>
<Value name="9">
<Value>Note</Value>
</Value>
<Value name="10">
<Value>UpdatedAt</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.PriceTableD</DataLocation>
<DefaultData>PriceTableDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.PriceTableD</IdLocation>
<IndexLocation>^AgenticProd.Data.PriceTableI</IndexLocation>
<StreamLocation>^AgenticProd.Data.PriceTableS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
