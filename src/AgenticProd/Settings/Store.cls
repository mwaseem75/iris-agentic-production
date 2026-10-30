/// Read and write the AI settings behind the dashboard's Settings tab.
/// Provider configs live in the AI Hub Config Store (AI.LLM.<name>), their API keys in the IRIS
/// Wallet (COLLECTION.<name>), referenced as secret://; agent, budget and mode values are
/// production item settings. Keys are write-only: nothing here returns one.
/// Learned mappings (Data.LearnedMapping) are listed and revoked here too, as memory.
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

/// Provider kinds build 154 accepts with api_key and base_url.
Parameter PROVIDERS = "openai,anthropic,openrouter,nim";

/// Kinds with no provider of their own on build 154: run as model_provider openai against their
/// OpenAI-compatible base_url, and remembered as display_kind (stripped before Provider.Create).
Parameter COMPATKINDS = "azure_openai,ollama";

/// Item settings each section may change, as item:field; anything else is refused.
Parameter AGENTFIELDS = "TriageAgent:ProviderConfig,TriageAgent:Model,TriageAgent:Temperature,TriageAgent:MaxIterations,TriageAgent:MaxToolCalls,TriageAgent:MaxTokensPerMessage,TriageAgent:DisabledSkills";

Parameter GUARDFIELDS = "TriageAgent:ToolTiers,TriageAgent:EnabledTiers,Triage:AutoFixDisabled,Triage:AutoFixThreshold,Triage:GroundingStrictness";

Parameter BUDGETFIELDS = "TriageAgent:DailyTokenBudget,TriageAgent:Mode,TriageAgent:KillSwitch";

/// Item -> class, for a setting's default when the production does not set it.
Parameter ITEMCLASSES = "TriageAgent=AgenticProd.Operation.Agent,Triage=AgenticProd.Process.Triage";

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
			Continue:(tKey="model")||(tKey="model_provider")||(tKey="display_kind")||(tVal="")
			Do pSettings.%Set(tKey, tVal)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Provider configs with key status "set" / "not set"; never the key.
/// build 154: the Config Store table shows a user without %Admin_ConfigStore no rows (no error),
/// so the names also come from the change log; details come from GetDetails (READRESOURCE).
ClassMethod Providers() As %DynamicArray
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, FullyQualifiedName FROM %ConfigStore.Configuration WHERE Area = 'AI' AND Type = 'LLM'")
	If tRS.%SQLCODE >= 0 {
		While tRS.%Next() {
			// Subtyped entries (AI.LLM.<subtype>.<name>) are not ours to show
			Set:tRS.FullyQualifiedName=..FQN(tRS.Name) tNames(tRS.Name) = ""
		}
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT %EXACT(Item) AS Item FROM AgenticProd_Data.SettingsAudit WHERE Scope = 'providers' AND Field = 'created'")
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	While tRS.%Next() { Set tNames(tRS.Item) = "" }
	Set tList = [], tName = ""
	For {
		Set tName = $ORDER(tNames(tName))
		Quit:tName=""
		// Deleted since, or not readable for this user
		Continue:$$$ISERR(##class(%ConfigStore.Configuration).GetDetails(..FQN(tName), .tDetails, 0, 0))
		Set tRow = {"name":(tName), "model_provider":(tDetails.%Get("model_provider")), "model":(tDetails.%Get("model")), "base_url":(tDetails.%Get("base_url"))}
		Set tRow.kind = $SELECT(tDetails.%Get("display_kind") '= "": tDetails.%Get("display_kind"), 1: tDetails.%Get("model_provider"))
		Set tRow.key = ..KeyStatus(tName)
		Do tList.%Push(tRow)
	}
	Quit tList
}

/// "set" or "not set". build 154: %Wallet.KeyValue.Exists answers 0 for a user without the
/// collection's use resource, so for them (the reviewer) the change log decides.
ClassMethod KeyStatus(pName As %String) As %String
{
	If $SYSTEM.Security.Check(..#USERESOURCE, "USE") {
		Quit $SELECT(##class(%Wallet.KeyValue).Exists(..#COLLECTION_"."_pName): "set", 1: "not set")
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.SettingsAudit WHERE Scope = 'keys' AND Item = ?", pName)
	Quit:(tRS.%SQLCODE<0)||'tRS.%Next() "not set"
	Quit $SELECT(tRS.N: "set", 1: "not set")
}

/// Create or update provider config pData.name: kind (PROVIDERS or COMPATKINDS; model_provider
/// is taken as the kind when kind is missing), model, base_url. A compatible kind needs base_url.
/// The api_key field always points at the Wallet; the key itself is set with SetKey.
ClassMethod SaveProvider(pData As %DynamicObject) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tName = pData.%Get("name")
		$$$ThrowOnError(..CheckName(tName))
		Set tKind = $SELECT(pData.%Get("kind") '= "": pData.%Get("kind"), 1: pData.%Get("model_provider"))
		Set tCompat = $LISTFIND($LISTFROMSTRING(..#COMPATKINDS), tKind) > 0
		If 'tCompat, '$LISTFIND($LISTFROMSTRING(..#PROVIDERS), tKind) $$$ThrowStatus($$$ERROR($$$GeneralError, "kind must be one of "_..#PROVIDERS_","_..#COMPATKINDS))
		Set tNew("model_provider") = $SELECT(tCompat: "openai", 1: tKind)
		Set tNew("display_kind") = $SELECT(tCompat: tKind, 1: "")
		Set tNew("model") = pData.%Get("model")
		Set tNew("base_url") = pData.%Get("base_url")
		If (tNew("model")'?1.100(1AN,1P))||(tNew("model")[" ") $$$ThrowStatus($$$ERROR($$$GeneralError, "model is required, no spaces"))
		If (tNew("base_url")'=""),$ZCONVERT($PIECE(tNew("base_url"), "://"), "L")'?1"http"0.1"s" $$$ThrowStatus($$$ERROR($$$GeneralError, "base_url must start with http:// or https://"))
		If tCompat, tNew("base_url") = "" $$$ThrowStatus($$$ERROR($$$GeneralError, tKind_" runs as OpenAI-compatible: base_url is required"))

		Set tDetails = {"model_provider":(tNew("model_provider")), "model":(tNew("model")), "api_key":("secret://"_..#COLLECTION_"."_tName_"#api_key")}
		Set:tNew("base_url")'="" tDetails."base_url" = tNew("base_url")
		Set:tCompat tDetails."display_kind" = tKind
		Set tFQN = ..FQN(tName)
		If ##class(%ConfigStore.Configuration).Exists(tFQN) {
			$$$ThrowOnError(##class(%ConfigStore.Configuration).GetDetails(tFQN, .tOld, 0, 0))
			$$$ThrowOnError(##class(%ConfigStore.Configuration).Modify(tFQN, tDetails))
			For tField = "model_provider", "display_kind", "model", "base_url" {
				Continue:tOld.%Get(tField)=tNew(tField)
				$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("providers", tName, tField, tOld.%Get(tField), tNew(tField)))
			}
		} Else {
			$$$ThrowOnError(##class(%ConfigStore.Configuration).Create("AI", "LLM", "", tName, tDetails, tName, "AgenticProd provider (Settings page)", ..#READRESOURCE, ..#EDITRESOURCE))
			$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("providers", tName, "created", "", tKind_" "_tNew("model")_$SELECT(tNew("base_url")'="": " "_tNew("base_url"), 1: "")))
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

/// Production item setting, or the item class's InitialExpression when the production leaves it unset.
ClassMethod Setting(pItem As %String, pField As %String) As %String
{
	Set tValue = ##class(Ens.Director).GetHostSettingValue(pItem, pField, .tSC)
	Quit:$$$ISOK(tSC)&&(tValue'="") tValue
	Set tClass = ""
	For i = 1:1:$LENGTH(..#ITEMCLASSES, ",") {
		Set:$PIECE($PIECE(..#ITEMCLASSES, ",", i), "=")=pItem tClass = $PIECE($PIECE(..#ITEMCLASSES, ",", i), "=", 2)
	}
	Set tProp = ##class(%Dictionary.CompiledProperty).%OpenId(tClass_"||"_pField)
	Quit $SELECT($IsObject(tProp): $ZSTRIP(tProp.InitialExpression, "<>", """"), 1: "")
}

/// Current values of pFields (item:field comma list), keyed by field.
ClassMethod ItemSettings(pFields As %String) As %DynamicObject
{
	Set tObj = {}
	For i = 1:1:$LENGTH(pFields, ",") {
		Set tPair = $PIECE(pFields, ",", i)
		Do tObj.%Set($PIECE(tPair, ":", 2), ..Setting($PIECE(tPair, ":"), $PIECE(tPair, ":", 2)))
	}
	Quit tObj
}

/// Apply pData (field: value); pSection agents, guardrails or budgets decides which fields are
/// allowed and on which item. Through Ens.Production.ApplySettings, so a running item restarts.
/// pNote: set when the values were saved but an item did not restart in time (it picks them up
/// when it does); that is not an error.
ClassMethod SaveItemSettings(pSection As %String, pData As %DynamicObject, Output pNote As %String) As %Status
{
	Set tSC = $$$OK, pNote = ""
	Try {
		Set tAllowed = $CASE(pSection, "agents": ..#AGENTFIELDS, "guardrails": ..#GUARDFIELDS, "budgets": ..#BUDGETFIELDS, : "")
		If tAllowed = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "Unknown settings section "_pSection))
		For i = 1:1:$LENGTH(tAllowed, ",") Set tItemOf($PIECE($PIECE(tAllowed, ",", i), ":", 2)) = $PIECE($PIECE(tAllowed, ",", i), ":")
		Set tIter = pData.%GetIterator()
		While tIter.%GetNext(.tField, .tVal) {
			If '$DATA(tItemOf(tField)) $$$ThrowStatus($$$ERROR($$$GeneralError, "Not a "_pSection_" setting: "_tField))
			// JSON true/false arrive as 1/0 already; normalise numbers like "8" and 8
			Set tVal = $SELECT($ISVALIDNUM(tVal): +tVal, 1: tVal)
			$$$ThrowOnError(..CheckItemSetting(tField, tVal))
			Set tItem = tItemOf(tField), tOld = ..Setting(tItem, tField)
			// "0.85" in the production file is .85 here: no change
			Continue:(tOld=tVal)||($ISVALIDNUM(tOld)&&$ISVALIDNUM(tVal)&&(tOld'="")&&(+tOld=tVal))
			Set tSettings(tItem, "Host", tField) = tVal, tOldOf(tField) = tOld
		}
		Quit:'$DATA(tSettings)
		Set tApplySC = ..ApplyQuietly(.tSettings)
		// The config is saved before the item restarts: a restart timeout (the agent item's
		// OnInit takes ~20 s) still leaves the new values in force, so log what was saved
		Set tItem = "", tSaved = 0
		For {
			Set tItem = $ORDER(tSettings(tItem))
			Quit:tItem=""
			Set tField = ""
			For {
				Set tField = $ORDER(tSettings(tItem, "Host", tField), 1, tVal)
				Quit:tField=""
				Continue:..Setting(tItem, tField)'=tVal
				Set tSaved = tSaved + 1
				$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log(pSection, tItem, tField, tOldOf(tField), tVal))
			}
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
			"AutoFixThreshold": $ISVALIDNUM(pValue) && (pValue >= 0) && (pValue <= 1),
			"GroundingStrictness": (",off,warn,enforce," [ (","_pValue_",")) && (pValue '= ""),
			"EnabledTiers": (pValue = "readonly") || (pValue = "readonly,write") || (pValue = "readonly,write,critical"),
			"ToolTiers": ..ListOK(pValue, "tiers"),
			"DisabledSkills": ..ListOK(pValue, "skills"),
			"AutoFixDisabled": ..ListOK(pValue, "classes"),
			: 0)
	}
	Quit:tOK $$$OK
	Quit $$$ERROR($$$GeneralError, "Invalid value for "_pField_": "_pValue)
}

/// Comma list check: "tiers" = tool=tier pairs (tool name, tier write or critical), "skills" =
/// skill classes from TriageAgent's SKILLS, "classes" = error classes. Empty is fine.
ClassMethod ListOK(pValue As %String, pKind As %String) As %Boolean [ Internal ]
{
	Quit:pValue="" 1
	Set tSkills = $LISTFROMSTRING(##class(AgenticProd.Agent.TriageAgent).#SKILLS)
	Set tClasses = $LISTFROMSTRING($EXTRACT(##class(AgenticProd.Msg.ErrorClass).#VALUELIST, 2, *))
	Set tOK = 1
	For i = 1:1:$LENGTH(pValue, ",") {
		Set tItem = $PIECE(pValue, ",", i)
		If pKind = "tiers" {
			Set tOK = ($PIECE(tItem, "=")?1L.63(1L,1N,1"_")) && ($LENGTH(tItem, "=") = 2) && (",write,critical," [ (","_$PIECE(tItem, "=", 2)_",")) && ($PIECE(tItem, "=", 2) '= "")
		} ElseIf pKind = "skills" {
			Set tOK = $LISTFIND(tSkills, tItem) > 0
		} Else {
			Set tOK = $LISTFIND(tClasses, tItem) > 0
		}
		Quit:'tOK
	}
	Quit tOK
}

/// The triage agent's tools as AI Hub lists them (no LLM call), with the tier the policy gives
/// each: [{name, provider, description, requiresAuth, tier}].
ClassMethod Tools() As %DynamicArray
{
	Set tAgent = ##class(AgenticProd.Agent.TriageAgent).%New()
	$$$ThrowOnError(tAgent.%Init())
	Set tPolicy = ##class(AgenticProd.Policy.ReadOnly).%New()
	Set tPolicy.ToolTiers = ..Setting(..#AGENTITEM, "ToolTiers")
	Set tOut = [], tIter = tAgent.ToolManager.GetToolStatuses().%GetIterator()
	While tIter.%GetNext(, .tTool) {
		Set tDesc = tTool.description
		Set tRow = {"name":(tTool.name), "provider":(tTool.provider), "description":($EXTRACT(tDesc, 1, 160)_$SELECT($LENGTH(tDesc) > 160: "...", 1: ""))}
		Do tRow.%Set("requiresAuth", ''tTool."requires_auth", "boolean")
		Set tRow.tier = tPolicy.TierOf(tTool.name, {"requires_auth":(''tTool."requires_auth")})
		Do tOut.%Push(tRow)
	}
	Quit tOut
}

/// TriageAgent's skills with their SUMMARY name and description, and whether this item uses them.
ClassMethod Skills() As %DynamicArray
{
	Set tDisabled = $LISTFROMSTRING(..Setting(..#AGENTITEM, "DisabledSkills"))
	Set tAll = ##class(AgenticProd.Agent.TriageAgent).#SKILLS, tOut = []
	For i = 1:1:$LENGTH(tAll, ",") {
		Set tClass = $ZSTRIP($PIECE(tAll, ",", i), "<>W")
		Continue:tClass=""
		Set tRow = {"class":(tClass), "name":(tClass), "description":""}
		Set tLines = $TRANSLATE(..XDataText(tClass, "SUMMARY"), $CHAR(13))
		For j = 1:1:$LENGTH(tLines, $CHAR(10)) {
			Set tLine = $PIECE(tLines, $CHAR(10), j), tKey = $ZSTRIP($PIECE(tLine, ":"), "<>W")
			Do:(tKey="name")||(tKey="description") tRow.%Set(tKey,$ZSTRIP($PIECE(tLine, ":", 2, *), "<>W", """"))
		}
		Do tRow.%Set("enabled", '$LISTFIND(tDisabled, tClass), "boolean")
		Do tOut.%Push(tRow)
	}
	Quit tOut
}

/// Text of XData block pName in pClass ("" when missing).
ClassMethod XDataText(pClass As %String, pName As %String) As %String
{
	Set tXData = ##class(%Dictionary.CompiledXData).%OpenId(pClass_"||"_pName)
	Quit:'$IsObject(tXData) ""
	Do tXData.Data.Rewind()
	Quit tXData.Data.Read(32000)
}

/// The AI kill switch: on, every failure goes to a person without an LLM call. Reaches this
/// production's agent and the AI.Agent item of every plug-in install in other namespaces.
ClassMethod SetKillSwitch(pOn As %Boolean, Output pNote As %String) As %Status
{
	Set tValue = $SELECT(pOn: 1, 1: 0)
	Set tSC = ..SaveItemSettings("budgets", {"KillSwitch":(tValue)}, .pNote)
	Quit:$$$ISERR(tSC) tSC
	Set tSC = ##class(AgenticProd.Plugin.Installer).ApplyAgentSetting("KillSwitch", tValue, .tNote)
	Set:tNote'="" pNote = pNote_$SELECT(pNote '= "": " ", 1: "")_tNote
	Quit tSC
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

/// Learned mappings, Active first then newest, each with "routed": the header IDs of messages
/// that went out with it since it was learned (see RoutedWith).
ClassMethod Memory() As %DynamicArray
{
	Set tRows = ##class(AgenticProd.UI.REST).Rows("SELECT ID, Namespace, CodeTable, LocalCode, Source, Loinc, Display, Origin, DecisionLogId, AgentSessionId, Evidence, Reviewer, ApprovedAt, Warning, Status, RevokedBy, RevokedAt, RevokeReason FROM AgenticProd_Data.LearnedMapping ORDER BY CASE WHEN Status = 'Active' THEN 0 ELSE 1 END, ID DESC")
	Set tIter = tRows.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Do tRow.%Set("routed", ..RoutedWith(tRow.LocalCode, tRow.ApprovedAt, tRow.DecisionLogId).%Size())
	}
	Quit tRows
}

/// Header IDs of messages routed with a mapping of pCode learned at pSince: the ones that passed
/// LabRouter on it (Data.SavedCall) and the failed message its approval resent (DecisionLog row
/// pLogId). Their FHIR results are in the same sessions. A seed has no such record: [].
ClassMethod RoutedWith(pCode As %String, pSince As %String, pLogId As %String = "") As %DynamicArray
{
	Set tList = []
	If pLogId '= "" {
		Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pLogId)
		If $IsObject(tLog), tLog.Outcome = "APPROVED" Do tList.%Push(tLog.HeaderId)  Set tSeen(tLog.HeaderId) = ""
	}
	// SavedCall.Note writes after the approval; ApprovedAt and CreatedAt are both UTC
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT HeaderId FROM AgenticProd_Data.SavedCall WHERE CreatedAt >= ? AND ','||LocalCodes||',' [ ? ORDER BY ID", pSince, ","_pCode_",")
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	While tRS.%Next() {
		Continue:$DATA(tSeen(tRS.HeaderId))
		Set tSeen(tRS.HeaderId) = ""
		Do tList.%Push(tRS.HeaderId)
	}
	Quit tList
}

/// Revoke learned mapping pId with pReason: remove its entry from the code table it was written
/// to, in its own namespace (when it still holds this LOINC), mark the row Revoked, and send a
/// review task for every message routed with it (MemoryReview, this production only). Logged in
/// SettingsAudit. pNote says how many tasks went out.
ClassMethod RevokeMapping(pId As %String, pReason As %String, Output pNote As %String) As %Status
{
	Set pNote = ""
	Set tSC = $$$OK
	Try {
		Set pReason = $ZSTRIP(pReason, "<>W")
		If pReason = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "A reason is required to revoke a mapping"))
		Set tRow = ##class(AgenticProd.Data.LearnedMapping).%OpenId(pId)
		If '$IsObject(tRow) $$$ThrowStatus($$$ERROR($$$GeneralError, "No learned mapping "_pId))
		If tRow.Status '= "Active" $$$ThrowStatus($$$ERROR($$$GeneralError, "Mapping "_pId_" is already revoked"))
		$$$ThrowOnError(..RemoveEntry(tRow))
		Set tRow.Status = "Revoked", tRow.RevokedBy = $USERNAME, tRow.RevokedAt = $ZDATETIME($ZTIMESTAMP, 3), tRow.RevokeReason = $EXTRACT(pReason, 1, 1000)
		$$$ThrowOnError(tRow.%Save())

		// MemoryReview and SavedCall belong to this production; a plug-in install has neither
		Set tHeaders = $SELECT(tRow.Namespace = $NAMESPACE: ..RoutedWith(tRow.LocalCode, tRow.ApprovedAt, tRow.DecisionLogId), 1: [])
		Set tTasks = ##class(%ListOfObjects).%New()
		Set tIter = tHeaders.%GetIterator()
		While tIter.%GetNext(, .tHeaderId) {
			Do tTasks.Insert(..RevokeTask(tRow, tHeaderId))
		}
		Set tSent = 0
		If tTasks.Count() {
			Set tSendSC = ##class(AgenticProd.Service.MemoryReview).Send(tTasks, .tSent)
			If $$$ISERR(tSendSC) Set pNote = (tTasks.Count() - tSent)_" review task(s) not sent: "_$SYSTEM.Status.GetErrorText(tSendSC)_". "
		}
		Set pNote = pNote_tSent_" review task(s) sent for messages routed with "_tRow.LocalCode_" -> "_tRow.Loinc_"."
		Set:tRow.Namespace'=$NAMESPACE pNote = pNote_" Removed from "_tRow.CodeTable_" in "_tRow.Namespace_"; check messages sent there with it at the receiver."
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("memory", tRow.LocalCode, "mapping", tRow.Loinc_" "_tRow.Display, "revoked: "_pReason_" ("_tSent_" review tasks)"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Take pRow's code out of its code table in its namespace, unless a newer mapping replaced it.
ClassMethod RemoveEntry(pRow As AgenticProd.Data.LearnedMapping) As %Status [ Internal ]
{
	New $NAMESPACE
	Set $NAMESPACE = pRow.Namespace
	Set tCurrent = ##class(Ens.Util.FunctionSet).Lookup(pRow.CodeTable, pRow.LocalCode)
	// Values are "LOINC^display" or the bare LOINC, per table
	Quit:$PIECE(tCurrent, "^")'=pRow.Loinc $$$OK
	Quit ##class(Ens.Util.LookupTable).%RemoveValue(pRow.CodeTable, pRow.LocalCode)
}

/// Review task for header pHeaderId, routed with revoked mapping pRow.
ClassMethod RevokeTask(pRow As AgenticProd.Data.LearnedMapping, pHeaderId As %Integer) As AgenticProd.Msg.ApprovalTask [ Internal ]
{
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).%New()
	Set tTask.HeaderId = pHeaderId, tTask.Decision = "ESCALATE", tTask.ErrorClass = "UNMAPPED_CODE"
	Set tTask.LocalCode = pRow.LocalCode, tTask.Loinc = pRow.Loinc, tTask.Display = pRow.Display
	Set tTask.Reason = "mapping revoked, please review: "_pRow.LocalCode_" -> "_pRow.Loinc_" ("_pRow.RevokeReason_")"
	Set tTask.%Actions = "Reviewed"
	Set tTask.%Subject = "Mapping revoked, please review message header "_pHeaderId
	Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
	Set tFHIR = $SELECT($IsObject(tHeader): ##class(AgenticProd.UI.REST).FHIRStatus(tHeader.SessionId), 1: "")
	Set tNL = $CHAR(13,10)
	Set tTask.%Message = "Message header "_pHeaderId_" was sent with "_pRow.LocalCode_" -> "_pRow.Loinc_" "_pRow.Display_"."_tNL
		_"That mapping was revoked by "_pRow.RevokedBy_" at "_pRow.RevokedAt_" (UTC): "_pRow.RevokeReason_tNL
		_$SELECT(tFHIR '= "": "FHIR bundle for the same session: "_tFHIR_tNL, 1: "")
		_"Check the result at the receiver and correct it there if the code was wrong."
	Quit tTask
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
