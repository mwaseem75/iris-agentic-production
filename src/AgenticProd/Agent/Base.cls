/// Agents whose provider can come from a Config Store entry chosen on the Settings page.
/// ProviderConfig empty: the subclass's PROVIDER/APIKEY parameters (.env key) as before.
Class AgenticProd.Agent.Base Extends %AI.Agent
{

/// Authorization policy class (built by the Workbench); empty for agents whose caller sets policies.
Parameter AUTHPOLICY As STRING;

/// Audit policy class; same rule as AUTHPOLICY.
Parameter AUDITPOLICY As STRING;

/// Tool rounds per message (outer loop limit); 0 keeps the AI Hub default.
Parameter MAXSTEPS = 0;

/// Daily spend limit in dollars, enforced by the production item that hosts the agent; 0 is none.
Parameter DAILYBUDGET = 0;

/// Config Store LLM entry name (AI.LLM.<name>); set before %Init().
Property ProviderConfig As %String(MAXLEN = 100);

/// Provider kind actually used (openai, anthropic, ...), for Data.Usage.
Property ProviderName As %String(MAXLEN = 50);

/// Attaches AUTHPOLICY/AUDITPOLICY only when no policy is set yet, so Operation.Agent, which sets
/// its own after %Init(), behaves as before.
Method %OnInit() As %Status
{
	Set tSC = $$$OK
	Try {
		Set:+..#MAXSTEPS ..MaxIterations = ..#MAXSTEPS
		Set tAuth = ..#AUTHPOLICY, tAudit = ..#AUDITPOLICY
		If (tAuth '= "") && '$IsObject(..ToolManager.AuthPolicy) {
			$$$ThrowOnError(..ToolManager.SetAuthPolicy($CLASSMETHOD(tAuth, "%New")))
		}
		If (tAudit '= "") && '$IsObject(..ToolManager.AuditPolicy) {
			$$$ThrowOnError(..ToolManager.SetAuditPolicy($CLASSMETHOD(tAudit, "%New")))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

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
