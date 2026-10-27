/// Unit tests for AgenticProd.Settings.Store, the settings REST writes and the kill switch.
/// Uses its own provider config, Wallet key and price row, removed afterwards. No LLM call:
/// %Init only builds the provider. Item settings are checked, never applied to the production.
Class AgenticProd.Test.Settings.StoreTest Extends %UnitTest.TestCase
{

Parameter TESTPROVIDER = "unittest_p";

Parameter TESTKEY = "sk-unittest-not-a-real-key-4242";

Parameter TESTMODEL = "unittest-model2";

Method TestProviderAndWriteOnlyKey()
{
	Set tName = ..#TESTPROVIDER
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "model_provider":"openai", "model":"gpt-4o-mini"}))
	Do $$$AssertEquals(..Provider(tName).key, "not set", "no key yet")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).ProviderSettings(tName, .tKind, .tModel, .tSettings), "no key: provider settings refused")

	Set tResult = ##class(AgenticProd.UI.REST).SettingsApply("key", {"name":(tName), "key":(..#TESTKEY)}, .tSC)
	Do $$$AssertStatusOK(tSC)
	Do $$$AssertEquals(tResult.key, "set")
	Do $$$AssertNotTrue(tResult.%ToJSON() [ ..#TESTKEY, "key not echoed")
	Do $$$AssertEquals(..Provider(tName).key, "set")
	Do $$$AssertNotTrue(##class(AgenticProd.UI.REST).SettingsData().%ToJSON() [ ..#TESTKEY, "key not in GET /settings")

	// The agent side resolves the secret:// reference to the Wallet value
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).ProviderSettings(tName, .tKind, .tModel, .tSettings))
	Do $$$AssertEquals(tKind, "openai")
	Do $$$AssertEquals(tModel, "gpt-4o-mini")
	Do $$$AssertEquals(tSettings."api_key", ..#TESTKEY)
	Do $$$AssertNotTrue(tSettings.%IsDefined("model"), "model is not a provider field")

	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "model_provider":"openai", "model":"gpt-5-nano"}))
	Do $$$AssertEquals(..Provider(tName).model, "gpt-5-nano")

	Set tLog = ##class(AgenticProd.UI.REST).Rows("SELECT Scope, Field, OldValue, NewValue FROM AgenticProd_Data.SettingsAudit WHERE Item = ? ORDER BY ID", tName)
	Do $$$AssertEquals(tLog.%Size(), 3, "created, key, model change")
	Do $$$AssertEquals(tLog.%Get(0).Field, "created")
	Do $$$AssertEquals(tLog.%Get(1).Scope, "keys")
	Do $$$AssertEquals(tLog.%Get(1).NewValue, "changed")
	Do $$$AssertEquals(tLog.%Get(2).OldValue, "gpt-4o-mini")
	Do $$$AssertEquals(tLog.%Get(2).NewValue, "gpt-5-nano")
	Do $$$AssertNotTrue(tLog.%ToJSON() [ ..#TESTKEY, "key not in the change log")

	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":"Bad Name", "model_provider":"openai", "model":"x"}), "name with space")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "model_provider":"azure", "model":"x"}), "no azure provider on build 154")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "model_provider":"openai", "model":"x", "base_url":"ftp://x"}), "base_url scheme")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SetKey(tName, "has space"), "key with space")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SetKey("unittest_none", "sk-x"), "key for a missing provider")
}

/// Provider from the configured entry (no LLM call), and the .env fallback when none is set.
Method TestAgentProviderFromConfig()
{
	Set tName = ..#TESTPROVIDER
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "model_provider":"anthropic", "model":"claude-haiku-5-5"}))
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SetKey(tName, ..#TESTKEY))

	Set tAgent = ##class(AgenticProd.Agent.PingAgent).%New()
	Set tAgent.ProviderConfig = tName
	Set tAgent.Model = ""
	Do $$$AssertStatusOK(tAgent.%Init())
	Do $$$AssertEquals(tAgent.ProviderName, "anthropic")
	Do $$$AssertEquals(tAgent.Model, "claude-haiku-5-5", "model from the config when the agent has none")

	Set tAgent = ##class(AgenticProd.Agent.TriageAgent).%New()
	Do $$$AssertStatusOK(tAgent.%Init())
	Do $$$AssertEquals(tAgent.ProviderName, "openai", ".env default")

	Set tAgent = ##class(AgenticProd.Agent.PingAgent).%New()
	Set tAgent.ProviderConfig = "unittest_none"
	Do $$$AssertStatusNotOK(tAgent.%Init(), "a missing config fails, no silent fallback")
}

Method TestItemSettingChecks()
{
	For tOK = $LISTBUILD("Model", "gpt-5-nano"), $LISTBUILD("Temperature", ""), $LISTBUILD("Temperature", 0.2),
		$LISTBUILD("MaxIterations", 8), $LISTBUILD("MaxToolCalls", 0), $LISTBUILD("DailyTokenBudget", 200000),
		$LISTBUILD("Mode", "replay"), $LISTBUILD("KillSwitch", 1), $LISTBUILD("ProviderConfig", "") {
		Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).CheckItemSetting($LIST(tOK, 1), $LIST(tOK, 2)), $LISTTOSTRING(tOK, "="))
	}
	For tBad = $LISTBUILD("Model", "has space"), $LISTBUILD("Temperature", 3), $LISTBUILD("MaxIterations", 0),
		$LISTBUILD("MaxIterations", 21), $LISTBUILD("MaxToolCalls", -1), $LISTBUILD("Mode", "dry"),
		$LISTBUILD("KillSwitch", 2), $LISTBUILD("ProviderConfig", "unittest_none"), $LISTBUILD("RunAsUser", "x") {
		Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).CheckItemSetting($LIST(tBad, 1), $LIST(tBad, 2)), $LISTTOSTRING(tBad, "="))
	}
	// Refused before anything is applied
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveItemSettings("agents", {"RunAsUser":"_SYSTEM"}), "RunAsUser is not editable")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveItemSettings("budgets", {"Model":"gpt-5-nano"}), "Model is not a budgets field")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveItemSettings("other", {}), "unknown section")
}

/// Azure OpenAI / Ollama run as model_provider openai against their base_url; the label is kept
/// in Config Store but never reaches %AI.Provider.Create.
Method TestCompatibleKinds()
{
	Set tName = ..#TESTPROVIDER
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "kind":"ollama", "model":"llama3.2"}), "compatible kind needs base_url")
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveProvider({"name":(tName), "kind":"ollama", "model":"llama3.2", "base_url":"http://localhost:11434/v1"}))
	Set tRow = ..Provider(tName)
	Do $$$AssertEquals(tRow.kind, "ollama")
	Do $$$AssertEquals(tRow."model_provider", "openai")
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SetKey(tName, "ollama"))
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).ProviderSettings(tName, .tKind, .tModel, .tSettings))
	Do $$$AssertEquals(tKind, "openai")
	Do $$$AssertNotTrue(tSettings.%IsDefined("display_kind"), "label stripped for Provider.Create")
	Do $$$AssertEquals(tSettings."base_url", "http://localhost:11434/v1")
	Set tAgent = ##class(AgenticProd.Agent.PingAgent).%New()
	Set tAgent.ProviderConfig = tName
	Do $$$AssertStatusOK(tAgent.%Init(), "provider builds with the compatible settings")
}

/// Guardrail and agent values the Settings tab may write; the item settings are not applied.
Method TestGuardrailChecks()
{
	For tOK = $LISTBUILD("EnabledTiers", "readonly,write"), $LISTBUILD("ToolTiers", "get_segment=write,validate_fix=critical"),
		$LISTBUILD("ToolTiers", ""), $LISTBUILD("AutoFixDisabled", "BAD_FORMAT,MISSING_FIELD"), $LISTBUILD("AutoFixThreshold", 0.9),
		$LISTBUILD("GroundingStrictness", "warn"), $LISTBUILD("DisabledSkills", "AgenticProd.Skill.CodeMapping") {
		Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).CheckItemSetting($LIST(tOK, 1), $LIST(tOK, 2)), $LISTTOSTRING(tOK, "="))
	}
	For tBad = $LISTBUILD("EnabledTiers", "write"), $LISTBUILD("ToolTiers", "get_segment=readonly"), $LISTBUILD("ToolTiers", "get_segment"),
		$LISTBUILD("AutoFixDisabled", "NOT_A_CLASS"), $LISTBUILD("AutoFixThreshold", 1.5), $LISTBUILD("GroundingStrictness", "loose"),
		$LISTBUILD("DisabledSkills", "Some.Other.Skill") {
		Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).CheckItemSetting($LIST(tBad, 1), $LIST(tBad, 2)), $LISTTOSTRING(tBad, "="))
	}
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SaveItemSettings("guardrails", {"Model":"x"}), "Model is not a guardrail")

	Set tTools = ##class(AgenticProd.Settings.Store).Tools()
	Do $$$AssertEquals(tTools.%Size(), 9, "the triage agent's nine tools")
	Set tIter = tTools.%GetIterator(), tAllRead = 1
	While tIter.%GetNext(, .tTool) { Set:tTool.tier'="readonly" tAllRead = 0 }
	Do $$$AssertTrue(tAllRead, "all tools readonly by default")
	Do $$$AssertEquals(##class(AgenticProd.Settings.Store).Skills().%Size(), 2)
	Do $$$AssertTrue(##class(AgenticProd.Settings.Store).XDataText("AgenticProd.Agent.TriageAgent", "INSTRUCTIONS") [ "Triage agent")

	Do $$$AssertEquals(##class(AgenticProd.Operation.Agent).EnabledSkills(""), ##class(AgenticProd.Agent.TriageAgent).#SKILLS)
	Do $$$AssertEquals(##class(AgenticProd.Operation.Agent).EnabledSkills("AgenticProd.Skill.CodeMapping"), "AgenticProd.Skill.HL7Repair")
	Do $$$AssertEquals(##class(AgenticProd.Operation.Agent).EnabledSkills(##class(AgenticProd.Agent.TriageAgent).#SKILLS), " ", "all off is a blank, not the default list")
	Set tAgent = ##class(AgenticProd.Agent.TriageAgent).%New()
	Set tAgent.Skills = " "
	Do $$$AssertStatusOK(tAgent.%Init())
	Do $$$AssertEquals(tAgent.ToolManager.GetToolStatuses().%Size(), 3, "no skills: only the Tools.Base tools")
}

Method TestPrices()
{
	Set tModel = ..#TESTMODEL
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SavePrice({"Model":(tModel), "Provider":"test", "InputPer1M":1, "OutputPer1M":2}))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).Cost(tModel, 1000000, 0, 0, 0, .tCost))
	Do $$$AssertEquals(tCost, 1)
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SavePrice({"Model":(tModel), "InputPer1M":3}))
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SavePrice({"Model":(tModel), "InputPer1M":-1}), "negative rate")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Settings.Store).SavePrice({"Model":(tModel), "Note":"x"}), "not a price field")
	Set tLog = ##class(AgenticProd.UI.REST).Rows("SELECT Field, OldValue, NewValue FROM AgenticProd_Data.SettingsAudit WHERE Item = ? ORDER BY ID", tModel)
	Do $$$AssertEquals(tLog.%Size(), 4, "3 fields on create, 1 change")
	Do $$$AssertEquals(tLog.%Get(3).Field, "InputPer1M")
	Do $$$AssertEquals(tLog.%Get(3).NewValue, 3)
}

Method TestKillSwitchEscalatesWithoutAgent()
{
	Set tOp = ##class(AgenticProd.Operation.Agent).%New("TestAgentOp")
	Set tOp.KillSwitch = 1
	Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
	Set tRequest.HeaderId = -9103
	Set tRequest.ErrorClass = "UNMAPPED_CODE"
	Set tBefore = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.Usage").%Get(0).N
	Do $$$AssertStatusOK(tOp.Triage(tRequest, .tDecision))
	Do $$$AssertEquals(tDecision.Decision, "ESCALATE")
	Do $$$AssertTrue(tDecision.Reason [ "kill switch")
	Do $$$AssertEquals(tDecision.AgentSessionId, "", "no agent session")
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.Usage").%Get(0).N, tBefore, "no Usage row")
}

Method Provider(pName As %String) As %DynamicObject
{
	Set tIter = ##class(AgenticProd.Settings.Store).Providers().%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Return:tRow.name=pName tRow
	}
	Quit {}
}

Method OnAfterOneTest() As %Status
{
	Set tName = ..#TESTPROVIDER
	Do:##class(%ConfigStore.Configuration).Exists(##class(AgenticProd.Settings.Store).FQN(tName)) ##class(%ConfigStore.Configuration).Delete(##class(AgenticProd.Settings.Store).FQN(tName))
	Set tSecret = ##class(AgenticProd.Settings.Store).#COLLECTION_"."_tName
	Do:##class(%Wallet.KeyValue).Exists(tSecret) ##class(%Wallet.KeyValue).Delete(tSecret)
	Do ##class(AgenticProd.Data.PriceTable).ModelIdxDelete(..#TESTMODEL)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.SettingsAudit WHERE Item IN (?, ?)", tName, ..#TESTMODEL)
	Quit $$$OK
}

}
