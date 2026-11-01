/// Create-an-agent wizard: compose, rules policy, ready queries, save and the trial run with a stub.
/// No LLM: the Run step reads its answer from ^||AgenticProd.WizardStub. Saved classes are deleted again.
Class AgenticProd.Test.UI.WizardTest Extends AgenticProd.Test.Case
{

Method OnBeforeAllTests() As %Status
{
	Do ..Cleanup()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^||AgenticProd.WizardStub
	Do ..Cleanup()
	Quit $$$OK
}

ClassMethod Cleanup()
{
	// Leftovers of earlier builder test runs
	Do $SYSTEM.OBJ.DeletePackage("MyAI.WbTest", "-d")
	Do $SYSTEM.OBJ.Delete("MyAI.Agent.WbTestWizard", "-d")
	Do $SYSTEM.OBJ.Delete("MyAI.Policy.WbTestWizardRules", "-d")
}

ClassMethod Spec(pName As %String = "Wb test wizard") As %DynamicObject
{
	Quit {"name":(pName), "providerConfig":"openai_main", "model":"gpt-4o-mini",
		"instructions":"You triage failed messages. Read the error first, then the message.",
		"toolsets":["AgenticProd.Tools.Base"], "skills":["AgenticProd.Skill.HL7Repair"],
		"rules":{"protectPid":true, "audit":true, "custom":[{"arg":"topic", "op":"contains", "value":"secret"}], "maxSteps":6, "dailyBudget":0.5}}
}

Method TestIdOf()
{
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).IdOf("Orders triage"), "OrdersTriage")
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).IdOf("  lab-result  fixer "), "LabResultFixer")
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).IdOf("1st agent"), "", "must start with a letter")
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).IdOf("!!"), "")
}

Method TestComposeWithRules()
{
	Set tC = ##class(AgenticProd.UI.Wizard).Compose(..Spec())
	Do $$$AssertEquals(tC.errors.%Size(), 0, tC.errors.%ToJSON())
	Do $$$AssertEquals(tC.agentClass, "MyAI.Agent.WbTestWizard")
	Do $$$AssertEquals(tC.parts.%Size(), 2, "policy and agent")
	Set tPolicy = tC.parts.%Get(0).code, tAgent = tC.parts.%Get(1).code
	Do $$$AssertTrue(tPolicy [ "Class MyAI.Policy.WbTestWizardRules Extends AgenticProd.Policy.ReadOnly", "one policy class per agent")
	Do $$$AssertTrue(tPolicy [ "PID(1):5", "PID-5 fix refused")
	Do $$$AssertTrue(tPolicy [ "SECRET", "custom rule")
	Do $$$AssertTrue(tAgent [ "Parameter AUTHPOLICY = ""MyAI.Policy.WbTestWizardRules""", "agent points at the generated policy")
	Do $$$AssertTrue(tAgent [ "Parameter AUDITPOLICY = ""AgenticProd.Policy.Audit""", "log every call")
	Do $$$AssertTrue(tAgent [ "Parameter MAXSTEPS = 6;", "max steps")
	Do $$$AssertTrue(tAgent [ "Parameter DAILYBUDGET = .5;", "daily budget")
}

Method TestComposeWithoutRules()
{
	Set tSpec = ..Spec()
	Set tSpec.rules = {"protectPid":false, "audit":false, "custom":[], "maxSteps":0, "dailyBudget":0}
	Set tC = ##class(AgenticProd.UI.Wizard).Compose(tSpec)
	Do $$$AssertEquals(tC.errors.%Size(), 0, tC.errors.%ToJSON())
	Do $$$AssertEquals(tC.parts.%Size(), 1, "agent only")
	Set tAgent = tC.parts.%Get(0).code
	Do $$$AssertTrue(tAgent [ "Parameter AUTHPOLICY = ""AgenticProd.Policy.ReadOnly""", "read-only policy stays")
	Do $$$AssertTrue(tAgent [ "Parameter AUDITPOLICY = """";", "no audit")
	Do $$$AssertTrue(tAgent '[ "MAXSTEPS", "no limit written")
}

Method TestComposeEnvKey()
{
	Set tSpec = ..Spec()
	Set tSpec.providerConfig = "", tSpec.provider = "openai", tSpec.apiKey = "@{env:OPENAI_API_KEY}"
	Set tC = ##class(AgenticProd.UI.Wizard).Compose(tSpec)
	Do $$$AssertEquals(tC.errors.%Size(), 0, tC.errors.%ToJSON())
	Set tAgent = tC.parts.%Get(tC.parts.%Size() - 1).code
	Do $$$AssertTrue(tAgent [ "Parameter PROVIDER = ""openai"";", "provider from the environment")
	Do $$$AssertTrue(tAgent [ "Parameter APIKEY = ""@{env:OPENAI_API_KEY}"";", "key stays a reference")
	Do $$$AssertTrue(tAgent '[ "PROVIDERCONFIG", "no config entry")
	Set tSpec.apiKey = "sk-not-a-reference"
	Do $$$AssertTrue(##class(AgenticProd.UI.Wizard).Compose(tSpec).errors.%Size() > 0, "a literal key is refused")
}

Method TestComposeErrors()
{
	Set tSpec = ..Spec("")
	Do $$$AssertTrue(##class(AgenticProd.UI.Wizard).Compose(tSpec).errors.%Size() > 0, "name required")
	Set tSpec = ..Spec()
	Set tSpec.rules.custom = [{"arg":"topic", "op":"matches", "value":"x"}]
	Do $$$AssertTrue(##class(AgenticProd.UI.Wizard).Compose(tSpec).errors.%Size() > 0, "unknown rule kind refused")
	Set tSpec = ..Spec()
	Set tSpec.toolsets = ["No.Such.Tools"]
	Do $$$AssertTrue(##class(AgenticProd.UI.Wizard).Compose(tSpec).errors.%Size() > 0, "unknown tools refused")
	Set tSpec = ..Spec()
	Set tSpec.rules.maxSteps = 99
	Do $$$AssertTrue(##class(AgenticProd.UI.Wizard).Compose(tSpec).errors.%Size() > 0, "max steps capped")
}

Method TestIdentityPolicyBlocks()
{
	Set tPol = ##class(AgenticProd.UI.Wizard).Compose(..Spec()).policySpec
	Set tB = "AgenticProd.UI.Builder"
	Set tRes = $CLASSMETHOD(tB, "TestPolicy", tPol, "get_segment", {"headerId":1, "segmentRef":"PID"})
	Do $$$AssertEquals(tRes.allowed, 0, "PID read blocked")
	Do $$$AssertTrue(tRes.message [ "Patient identity is protected", "message for the agent")
	Set tRes = $CLASSMETHOD(tB, "TestPolicy", tPol, "get_segment", {"headerId":1, "segmentRef":"OBX(1)"})
	Do $$$AssertEquals(tRes.allowed, 1, "OBX allowed")
	Set tFix = [{"path":"PID(1):5", "from":"a", "to":"b"}].%ToJSON()
	Set tRes = $CLASSMETHOD(tB, "TestPolicy", tPol, "validate_fix", {"headerId":1, "fixJSON":(tFix)})
	Do $$$AssertEquals(tRes.allowed, 0, "fix on PID-5 blocked")
}

Method TestReadyQueriesRun()
{
	Set tIter = ##class(AgenticProd.UI.Wizard).ReadyQueries().%GetIterator()
	While tIter.%GetNext(, .tQ) {
		Set tSpec = {"class":"MyAI.WbTest.Ready", "tool":(tQ.tool), "description":(tQ.description), "maxRows":20,
			"args":[{"name":(tQ.arg), "type":($SELECT(tQ.arg="headerId": "%Integer", 1: "%String")), "required":true}], "sql":(tQ.sql)}
		Set tArgs = {}
		Do tArgs.%Set(tQ.arg, $SELECT(tQ.arg="headerId": 1, 1: tQ.example))
		Set tRes = ##class(AgenticProd.UI.Builder).TestTool(tSpec, tArgs)
		Do $$$AssertEquals(tRes.ok, 1, tQ.id_": "_tRes.errors.%ToJSON())
	}
}

Method TestSaveAndOptions()
{
	Set tRes = ##class(AgenticProd.UI.Wizard).Save(..Spec())
	Do $$$AssertEquals(tRes.saved, 1, tRes.errors.%ToJSON())
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("MyAI.Agent.WbTestWizard"), "agent compiled")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("MyAI.Policy.WbTestWizardRules"), "policy compiled")
	Do $$$AssertEquals($PARAMETER("MyAI.Agent.WbTestWizard", "MAXSTEPS"), 6)
	// Saving again updates the class the wizard wrote
	Set tAgain = ##class(AgenticProd.UI.Wizard).Save(..Spec())
	Do $$$AssertEquals(tAgain.saved, 1, tAgain.errors.%ToJSON())
	Set tOpts = ##class(AgenticProd.UI.Wizard).Options(1)
	Do $$$AssertEquals(tOpts.starters.%Size(), 3)
	Set (tBase, tSkill) = 0, tIter = tOpts.abilities.%GetIterator()
	While tIter.%GetNext(, .tA) {
		Set:tA.class="AgenticProd.Tools.Base" tBase = 1
		Set:tA.class="AgenticProd.Skill.HL7Repair" tSkill = 1
		Do $$$AssertTrue(tA.class '[ "WbTest", "test classes are not abilities")
		Do $$$AssertTrue(tA.class '= "AgenticProd.Tools.HL7", "a skill's own toolset is not listed twice")
	}
	Do $$$AssertEquals(tBase, 1, "toolset listed")
	Do $$$AssertEquals(tSkill, 1, "skill listed")
}

Method TestSourceHidesBuilderSpec()
{
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("tool", {"class":"MyAI.WbTest.Src", "tool":"get_x", "maxRows":5, "description":"Show the newest messages of one item.", "args":[{"name":"itemName", "type":"%String", "required":true}], "sql":"SELECT ID FROM Ens.MessageHeader WHERE TargetConfigName = :itemName"})
	Do $$$AssertTrue(tGen.code [ "BuilderSpec", "generated class carries the spec")
	Set tShown = ##class(AgenticProd.UI.Workbench).WithoutSpec(tGen.code)
	Do $$$AssertTrue(tShown '[ "BuilderSpec", "spec hidden")
	Do $$$AssertTrue(tShown '[ "Workbench form values", "its doc line hidden")
	Do $$$AssertTrue(tShown [ "<Query Name=""get_x""", "the tool stays")
}

Method TestRunWithStub()
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.DecisionLog")
	If 'tRS.%Next() {
		Do $$$LogMessage("no DecisionLog row; Run steps not tested")
		Quit
	}
	Set tSample = tRS.ID
	Set tSpec = ..Spec()
	// Without a stub the call would go to the model; the unit test run blocks it
	Set tRes = ##class(AgenticProd.UI.Wizard).Run(tSpec, tSample, 1)
	Do $$$AssertEquals(tRes.state, "blocked", "no live call from a test")
	Set tAnswer = {"decision":"ESCALATE", "error_class":"IDENTITY_ISSUE", "confidence":0.8, "fix":[], "validated":false, "evidence":["PID is protected"], "reason":"Identity fields need a person."}
	Set ^||AgenticProd.WizardStub = {"toolCalls":[
			{"tool":"get_error_events", "arguments":({"headerId":7}.%ToJSON()), "status":"OK", "error":""},
			{"tool":"get_segment", "arguments":({"headerId":7, "segmentRef":"PID"}.%ToJSON()), "status":"DENIED", "error":"Patient identity is protected. Escalate instead."},
			{"tool":"get_recent_messages", "arguments":({"itemName":"EhrOut"}.%ToJSON()), "status":"OK", "error":""}],
		"answer":(tAnswer.%ToJSON()), "promptTokens":1000, "completionTokens":100}.%ToJSON()
	If ##class(AgenticProd.UI.Wizard).KillSwitch() {
		Set tRes = ##class(AgenticProd.UI.Wizard).Run(tSpec, tSample, 1)
		Do $$$AssertEquals(tRes.state, "blocked", "kill switch blocks the run")
		Quit
	}
	Set tNeed = ##class(AgenticProd.UI.Wizard).Run(tSpec, tSample, 0)
	Do $$$AssertEquals(tNeed.state, "needs-confirm", "a live run needs the price confirmed")
	Set tRes = ##class(AgenticProd.UI.Wizard).Run(tSpec, tSample, 1)
	Do $$$AssertEquals(tRes.state, "ok", tRes.%ToJSON())
	Do $$$AssertEquals(tRes.steps.%Size(), 4)
	Do $$$AssertEquals(tRes.steps.%Get(0).text, "Read the error log")
	Do $$$AssertEquals(tRes.steps.%Get(1).kind, "blocked", "denied call shown")
	Do $$$AssertEquals(tRes.steps.%Get(1).text, "Tried: Read segment PID")
	Do $$$AssertEquals(tRes.steps.%Get(2).text, "Ran get recent messages (itemName = EhrOut)", "own tool in plain words")
	Do $$$AssertEquals(tRes.decision, "ESCALATE")
	Do $$$AssertEquals(tRes.promptTokens, 1000)
	Kill ^||AgenticProd.WizardStub
}

Method TestRunWithoutSample()
{
	Kill ^||AgenticProd.WizardStub
	Set tRes = ##class(AgenticProd.UI.Wizard).Run(..Spec(), 0, 1)
	Do $$$AssertTrue((tRes.state = "invalid") || (tRes.state = "blocked"), "no sample, no run: "_tRes.state)
	// Through Handle the HTTP status is "status", so the run result lives in "state"
	Set tHttp = ##class(AgenticProd.UI.Wizard).Handle("run", {"spec":(..Spec()), "sample":0, "confirm":1}, 1)
	Do $$$AssertEquals(tHttp.status, 200)
	Do $$$AssertTrue(tHttp.state '= "", "state survives Handle")
}

Method TestAdminOnly()
{
	Set tBody = {"spec":(..Spec())}
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).Handle("save", tBody, 0).status, 403)
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).Handle("run", tBody, 0).status, 403)
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).Handle("compose", tBody, 0).status, 200, "composing is only a preview")
	Do $$$AssertEquals(##class(AgenticProd.UI.Wizard).Handle("compose", {}, 1).status, 400)
}

}
