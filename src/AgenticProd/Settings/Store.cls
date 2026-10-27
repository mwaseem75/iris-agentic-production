/// Read and write the AI settings behind the dashboard's Settings tab.
/// Provider configs live in the AI Hub Config Store (AI.LLM.<name>), their API keys in the IRIS
/// Wallet (COLLECTION.<name>), referenced as secret://; agent, budget and mode values are
/// production item settings. Keys are write-only: nothing here returns one.
/// Every change is written to Data.SettingsAudit. Callers check the edit resource (UI.REST).
Class AgenticProd.Settings.Store Extends %RegisteredObject
{

Parameter COLLECTION = "AgenticProd";

/// Read provider configs (no secrets in them): dashboard, admin, agent.
Parameter READRESOURCE = "AgenticProd_AIRead";

/// Resolve the Wallet keys: admin (test connection) and the agent job only.
Parameter USERESOURCE = "AgenticProd_AIUse";

/// Change anything on the Settings tab; also the Wallet and config edit resource.
Parameter EDITRESOURCE = "AgenticProd_Settings";

Parameter PRODUCTION = "AgenticProd.Production";

Parameter AGENTITEM = "TriageAgent";

/// Provider kinds build 154 accepts with api_key and base_url (Ollama: openai + base_url).
/// Azure and Ollama have no provider of their own on this build.
Parameter PROVIDERS = "openai,anthropic,openrouter,nim";

/// Item settings each section may change; anything else is refused.
Parameter AGENTFIELDS = "ProviderConfig,Model,Temperature,MaxIterations,MaxToolCalls,MaxTokensPerMessage";

Parameter BUDGETFIELDS = "DailyTokenBudget,Mode,KillSwitch";

Parameter PRICEFIELDS = "Provider,InputPer1M,OutputPer1M,CacheReadPer1M,CacheWritePer1M";

/// Kept short so a test click costs a few tokens.
Parameter PINGTEXT = "Reply with the single word OK.";

/// Resources, the descriptor registry and the Wallet collection. Idempotent; Setup runs it
/// before AgentSecurity because the agent role lists these resources.
ClassMethod Prepare() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CreateResources())
		// build 154 ships the registry empty: without it Config Store refuses AI.LLM entries
		// ("No descriptor found for AI.LLM")
		$$$ThrowOnError(##class(%ConfigStore.DescriptorManager).GetDescriptorClass("AI", "LLM", "", .tClass))
		If tClass = "" $$$ThrowOnError(##class(%ConfigStore.DescriptorManager).RebuildRegistry())
		If '##class(%Wallet.Collection).Exists(..#COLLECTION) {
			$$$ThrowOnError(##class(%Wallet.Collection).Create(..#COLLECTION, {"UseResource":(..#USERESOURCE), "EditResource":(..#EDITRESOURCE)}))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod CreateResources() As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set tSC = $$$OK
	Try {
		For tRes = ..#READRESOURCE, ..#USERESOURCE, ..#EDITRESOURCE {
			// No public permission: holding the resource is the access check
			Continue:##class(Security.Resources).Exists(tRes)
			$$$ThrowOnError(##class(Security.Resources).Create(tRes, "AgenticProd settings", ""))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod FQN(pName As %String) As %String
{
	Quit "AI.LLM."_pName
}

/// Config names become Wallet key names too, so keep them plain.
ClassMethod CheckName(pName As %String) As %Status
{
	Quit:pName?1L.31(1L,1N,1"_") $$$OK
	Quit $$$ERROR($$$GeneralError, "Provider name must be lower case letters, digits or _, starting with a letter (max 32): "_pName)
}

/// Resolved settings for %AI.Provider.Create: secret:// references replaced by the Wallet value.
/// model and model_provider are returned apart; they are not provider fields.
ClassMethod ProviderSettings(pName As %String, Output pProvider As %String, Output pModel As %String, Output pSettings As %DynamicObject) As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(%ConfigStore.Configuration).GetDetails(..FQN(pName), .tDetails, 0, 1))
		Set pProvider = tDetails.%Get("model_provider"), pModel = tDetails.%Get("model")
		If pProvider = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "Provider config "_pName_" has no model_provider"))
		If tDetails.%Get("api_key") [ "secret://" $$$ThrowStatus($$$ERROR($$$GeneralError, "API key for provider config "_pName_" is not set"))
		Set pSettings = {}
		Set tIter = tDetails.%GetIterator()
		While tIter.%GetNext(.tKey, .tVal) {
			Continue:(tKey="model")||(tKey="model_provider")||(tVal="")
			Do pSettings.%Set(tKey, tVal)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Provider configs with key status "set" / "not set"; never the key.
ClassMethod Providers() As %DynamicArray
{
	Set tList = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, FullyQualifiedName, ModifiedAt FROM %ConfigStore.Configuration WHERE Area = 'AI' AND Type = 'LLM' ORDER BY Name")
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	While tRS.%Next() {
		Set tName = tRS.Name
		// Subtyped entries (AI.LLM.<subtype>.<name>) are not ours to show
		Continue:tRS.FullyQualifiedName'=..FQN(tName)
		Set tRow = {"name":(tName), "modifiedAt":(tRS.ModifiedAt)}
		If $$$ISOK(##class(%ConfigStore.Configuration).GetDetails(..FQN(tName), .tDetails, 0, 0)) {
			Set tRow."model_provider" = tDetails.%Get("model_provider")
			Set tRow.model = tDetails.%Get("model")
			Set tRow."base_url" = tDetails.%Get("base_url")
		}
		Set tRow.key = ..KeyStatus(tName)
		Do tList.%Push(tRow)
	}
	Quit tList
}

/// "set", "not set", or "unknown" when the caller may not even look.
ClassMethod KeyStatus(pName As %String) As %String
{
	Try {
		Set tStatus = $SELECT(##class(%Wallet.KeyValue).Exists(..#COLLECTION_"."_pName): "set", 1: "not set")
	} Catch {
		Set tStatus = "unknown"
	}
	Quit tStatus
}

/// Create or update provider config pData.name (model_provider, model, base_url). The api_key
/// field always points at the Wallet; the key itself is set with SetKey.
ClassMethod SaveProvider(pData As %DynamicObject) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tName = pData.%Get("name")
		$$$ThrowOnError(..CheckName(tName))
		Set tNew("model_provider") = pData.%Get("model_provider")
		Set tNew("model") = pData.%Get("model")
		Set tNew("base_url") = pData.%Get("base_url")
		If '$LISTFIND($LISTFROMSTRING(..#PROVIDERS), tNew("model_provider")) $$$ThrowStatus($$$ERROR($$$GeneralError, "model_provider must be one of "_..#PROVIDERS))
		If (tNew("model")'?1.100(1AN,1P))||(tNew("model")[" ") $$$ThrowStatus($$$ERROR($$$GeneralError, "model is required, no spaces"))
		If (tNew("base_url")'=""),$ZCONVERT($PIECE(tNew("base_url"), "://"), "L")'?1"http"0.1"s" $$$ThrowStatus($$$ERROR($$$GeneralError, "base_url must start with http:// or https://"))

		Set tDetails = {"model_provider":(tNew("model_provider")), "model":(tNew("model")), "api_key":("secret://"_..#COLLECTION_"."_tName_"#api_key")}
		Set:tNew("base_url")'="" tDetails."base_url" = tNew("base_url")
		Set tFQN = ..FQN(tName)
		If ##class(%ConfigStore.Configuration).Exists(tFQN) {
			$$$ThrowOnError(##class(%ConfigStore.Configuration).GetDetails(tFQN, .tOld, 0, 0))
			$$$ThrowOnError(##class(%ConfigStore.Configuration).Modify(tFQN, tDetails))
			For tField = "model_provider", "model", "base_url" {
				Continue:tOld.%Get(tField)=tNew(tField)
				$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("providers", tName, tField, tOld.%Get(tField), tNew(tField)))
			}
		} Else {
			$$$ThrowOnError(##class(%ConfigStore.Configuration).Create("AI", "LLM", "", tName, tDetails, tName, "AgenticProd provider (Settings page)", ..#READRESOURCE, ..#EDITRESOURCE))
			$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("providers", tName, "created", "", tNew("model_provider")_" "_tNew("model")_$SELECT(tNew("base_url")'="": " "_tNew("base_url"), 1: "")))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Store pKey as the API key of provider config pName. Write-only: logged as "changed".
ClassMethod SetKey(pName As %String, pKey As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CheckName(pName))
		If '##class(%ConfigStore.Configuration).Exists(..FQN(pName)) $$$ThrowStatus($$$ERROR($$$GeneralError, "No provider config "_pName_"; save the provider first"))
		If (pKey="")||($LENGTH(pKey)>500)||(pKey'=$ZSTRIP(pKey, "*W")) $$$ThrowStatus($$$ERROR($$$GeneralError, "Key must be 1-500 characters without spaces"))
		Set tSecret = ..#COLLECTION_"."_pName
		Set tHad = ##class(%Wallet.KeyValue).Exists(tSecret)
		If tHad {
			$$$ThrowOnError(##class(%Wallet.KeyValue).Modify(tSecret, {"Secret":{"api_key":(pKey)}}))
		} Else {
			$$$ThrowOnError(##class(%Wallet.KeyValue).Create(tSecret, {"Usage":"CUSTOM", "Secret":{"api_key":(pKey)}}))
		}
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("keys", pName, "api_key", $SELECT(tHad: "set", 1: "not set"), "changed"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Current values of the agent item's settings in pFields (comma list).
ClassMethod ItemSettings(pFields As %String) As %DynamicObject
{
	Set tObj = {}
	For i = 1:1:$LENGTH(pFields, ",") {
		Set tField = $PIECE(pFields, ",", i)
		Do tObj.%Set(tField, ##class(AgenticProd.UI.REST).AgentSetting(..#AGENTITEM, tField))
	}
	Quit tObj
}

/// Apply pData (field: value) to the agent item; pSection "agents" or "budgets" decides which
/// fields are allowed. Through Ens.Production.ApplySettings, so a running item restarts with them.
/// pNote: set when the values were saved but the item did not restart in time (it picks them up
/// when it does); that is not an error.
ClassMethod SaveItemSettings(pSection As %String, pData As %DynamicObject, Output pNote As %String) As %Status
{
	Set tSC = $$$OK, pNote = ""
	Try {
		Set tAllowed = $CASE(pSection, "agents": ..#AGENTFIELDS, "budgets": ..#BUDGETFIELDS, : "")
		If tAllowed = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "Unknown settings section "_pSection))
		Set tIter = pData.%GetIterator()
		While tIter.%GetNext(.tField, .tVal) {
			If '$LISTFIND($LISTFROMSTRING(tAllowed), tField) $$$ThrowStatus($$$ERROR($$$GeneralError, "Not a "_pSection_" setting: "_tField))
			// JSON true/false arrive as 1/0 already; normalise numbers like "8" and 8
			Set tVal = $SELECT($ISVALIDNUM(tVal): +tVal, 1: tVal)
			$$$ThrowOnError(..CheckItemSetting(tField, tVal))
			Set tOld = ##class(AgenticProd.UI.REST).AgentSetting(..#AGENTITEM, tField)
			Continue:tOld=tVal
			Set tSettings(..#AGENTITEM, "Host", tField) = tVal, tOldOf(tField) = tOld
		}
		Quit:'$DATA(tSettings)
		Set tApplySC = ..ApplyQuietly(.tSettings)
		// The config is saved before the item restarts: a restart timeout (the agent item's
		// OnInit takes ~20 s) still leaves the new values in force, so log what was saved
		Set tField = "", tSaved = 0
		For {
			Set tField = $ORDER(tSettings(..#AGENTITEM, "Host", tField), 1, tVal)
			Quit:tField=""
			Continue:##class(AgenticProd.UI.REST).AgentSetting(..#AGENTITEM, tField)'=tVal
			Set tSaved = tSaved + 1
			$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log(pSection, ..#AGENTITEM, tField, tOldOf(tField), tVal))
		}
		If $$$ISERR(tApplySC) {
			If 'tSaved $$$ThrowStatus(tApplySC)
			Set pNote = "Saved; the agent item has not restarted yet: "_$SYSTEM.Status.GetErrorText(tApplySC)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// ApplySettings writes progress lines to the current device; in a REST request that is the
/// HTTP response, so they go to the null device.
ClassMethod ApplyQuietly(ByRef pSettings) As %Status [ Private ]
{
	Set tIO = $IO, tNull = $SELECT($SYSTEM.Version.GetOS() = "Windows": "//./nul", 1: "/dev/null")
	Open tNull
	Use tNull
	Try {
		Set tSC = ##class(Ens.Production).ApplySettings(..#PRODUCTION, .pSettings)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Use tIO
	Close tNull
	Quit tSC
}

/// Same ranges as the Operation.Agent properties, checked before anything is applied.
ClassMethod CheckItemSetting(pField As %String, pValue As %String) As %Status
{
	If pField = "ProviderConfig" {
		Set tOK = (pValue = "") || ($$$ISOK(..CheckName(pValue)) && ##class(%ConfigStore.Configuration).Exists(..FQN(pValue)))
	} Else {
		Set tOK = $CASE(pField,
			"Model": (pValue?1.100(1AN,1P)) && (pValue'[" "),
			"Temperature": (pValue = "") || ($ISVALIDNUM(pValue) && (pValue >= 0) && (pValue <= 2)),
			"MaxIterations": (pValue?1.2N) && (pValue >= 1) && (pValue <= 20),
			"MaxToolCalls": pValue?1.6N,
			"MaxTokensPerMessage": pValue?1.9N,
			"DailyTokenBudget": pValue?1.12N,
			"Mode": (pValue = "live") || (pValue = "replay"),
			"KillSwitch": (pValue = 0) || (pValue = 1),
			: 0)
	}
	Quit:tOK $$$OK
	Quit $$$ERROR($$$GeneralError, "Invalid value for "_pField_": "_pValue)
}

/// The AI kill switch: on, every failure goes to a person without an LLM call.
ClassMethod SetKillSwitch(pOn As %Boolean, Output pNote As %String) As %Status
{
	Quit ..SaveItemSettings("budgets", {"KillSwitch":($SELECT(pOn: 1, 1: 0))}, .pNote)
}

ClassMethod Prices() As %DynamicArray
{
	Quit ##class(AgenticProd.UI.REST).Rows("SELECT Provider, Model, InputPer1M, OutputPer1M, CacheReadPer1M, CacheWritePer1M, UpdatedAt FROM AgenticProd_Data.PriceTable ORDER BY Provider, Model")
}

/// Add or change the price row of pData.Model; only PRICEFIELDS are taken.
ClassMethod SavePrice(pData As %DynamicObject) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tModel = pData.%Get("Model")
		If (tModel'?1.100(1AN,1P))||(tModel[" ") $$$ThrowStatus($$$ERROR($$$GeneralError, "Model is required, no spaces"))
		Set tRow = ##class(AgenticProd.Data.PriceTable).ModelIdxOpen(tModel)
		Set tNew = '$IsObject(tRow)
		If tNew {
			Set tRow = ##class(AgenticProd.Data.PriceTable).%New()
			Set tRow.Model = tModel
		}
		Set tIter = pData.%GetIterator()
		While tIter.%GetNext(.tField, .tVal) {
			Continue:tField="Model"
			If '$LISTFIND($LISTFROMSTRING(..#PRICEFIELDS), tField) $$$ThrowStatus($$$ERROR($$$GeneralError, "Not a price field: "_tField))
			If tField '= "Provider", '$ISVALIDNUM(tVal) || (tVal < 0) $$$ThrowStatus($$$ERROR($$$GeneralError, tField_" must be a number >= 0"))
			Set tOld = $PROPERTY(tRow, tField)
			Continue:'tNew&&(tOld=tVal)
			Set $PROPERTY(tRow, tField) = tVal, tChanged(tField) = $LISTBUILD(tOld, tVal)
		}
		Quit:'$DATA(tChanged)
		Set tRow.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3)
		Set tRow.Note = "Settings page, "_$USERNAME
		$$$ThrowOnError(tRow.%Save())
		Set tField = ""
		For {
			Set tField = $ORDER(tChanged(tField), 1, tPair)
			Quit:tField=""
			$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("prices", tModel, tField, $LIST(tPair, 1), $LIST(tPair, 2)))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod ChangeLog(pLimit As %Integer = 50) As %DynamicArray
{
	Quit ##class(AgenticProd.UI.REST).Rows("SELECT TOP ? ChangedAt, ChangedBy, Scope, Item, Field, OldValue, NewValue FROM AgenticProd_Data.SettingsAudit ORDER BY ID DESC", pLimit)
}

/// One Chat with PINGTEXT on provider config pName ("" = the .env default) and pModel
/// ("" = the config's model). Real LLM call: one per click, recorded in Data.Usage (Decision
/// TEST) so it counts against the daily budget. pResult: ok, reply or error, tokens, cost.
ClassMethod TestConnection(pName As %String, pModel As %String, Output pResult As %DynamicObject) As %Status
{
	Set tSC = $$$OK, tSession = ""
	Set pResult = {"ok":false, "provider":(pName)}
	Try {
		Set tStart = $ZHOROLOG
		Set tAgent = ##class(AgenticProd.Agent.PingAgent).%New()
		Set tAgent.ProviderConfig = pName
		Set:pModel'="" tAgent.Model = pModel
		$$$ThrowOnError(tAgent.%Init())
		Set tSession = tAgent.CreateSession({"max_iterations":1})
		$$$ThrowOnError(tSession.%Save())
		Set tResponse = tAgent.Chat(tSession, ..#PINGTEXT)
		$$$ThrowOnError(tSession.%Save())
		Set tStats = tSession.GetStats()
		Set tUsage = ##class(AgenticProd.Data.Usage).FromStats(tStats, tAgent.ProviderName, tAgent.Model)
		Set tUsage.AgentSessionId = tSession.%Id()
		Set tUsage.Decision = "TEST"
		Set tUsage.TotalMs = ($ZHOROLOG - tStart) * 1000 \ 1
		$$$ThrowOnError(tUsage.%Save())
		Do pResult.%Set("ok", 1, "boolean")
		Set pResult.model = tAgent.Model
		Set pResult.kind = tAgent.ProviderName
		Set pResult.reply = $EXTRACT(tResponse.Content, 1, 200)
		Set pResult.promptTokens = tUsage.PromptTokens
		Set pResult.completionTokens = tUsage.CompletionTokens
		Do pResult.%Set("costUsd", tUsage.CostUsd, $SELECT(tUsage.CostUsd = "": "null", 1: "number"))
		Set pResult.ms = tUsage.TotalMs
		Set pResult.sessionId = tSession.%Id()
		Set tNote = "ok "_tAgent.Model_" "_tUsage.PromptTokens_"+"_tUsage.CompletionTokens_" tokens"
	} Catch ex {
		// The provider's message only; it masks keys itself (OpenAI shows the last 4 characters)
		Set pResult.error = $EXTRACT($SYSTEM.Status.GetErrorText(ex.AsStatus()), 1, 500)
		Set tNote = "failed: "_$EXTRACT(pResult.error, 1, 200)
		If $IsObject(tSession) Do tSession.%Save()
	}
	Set tSC = ##class(AgenticProd.Data.SettingsAudit).Log("test", $SELECT(pName = "": "(.env)", 1: pName), "test-connection", "", tNote)
	Quit tSC
}

}
