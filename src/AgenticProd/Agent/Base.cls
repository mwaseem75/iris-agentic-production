/// Agents whose provider can come from a Config Store entry chosen on the Settings page.
/// ProviderConfig empty: the subclass's PROVIDER/APIKEY parameters (.env key) as before.
Class AgenticProd.Agent.Base Extends %AI.Agent
{

/// Config Store LLM entry name (AI.LLM.<name>); set before %Init().
Property ProviderConfig As %String(MAXLEN = 100);

/// Provider kind actually used (openai, anthropic, ...), for Data.Usage.
Property ProviderName As %String(MAXLEN = 50);

/// build 154: PROVIDERCONFIG is a class parameter, so a config picked at run time has to be
/// loaded here. Provider.Create rejects unknown fields, so only the entry's own fields are passed.
Method %CreateProvider() As %Status [ Internal ]
{
	If ..ProviderConfig = "" {
		Set ..ProviderName = ..#PROVIDER
		Quit ##super()
	}
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(AgenticProd.Settings.Store).ProviderSettings(..ProviderConfig, .tProvider, .tModel, .tSettings))
		Set:..Model="" ..Model = tModel
		Set ..ProviderName = tProvider
		Set ..Provider = ##class(%AI.Provider).Create(tProvider, tSettings)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
