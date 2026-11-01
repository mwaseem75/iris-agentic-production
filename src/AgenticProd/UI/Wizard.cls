/// Workbench "Create an agent" wizard: one spec (goal, abilities, rules) in, up to two generated
/// classes out (a rules policy and the agent), plus one live trial run. All code generation is
/// AgenticProd.UI.Builder; this class only maps plain-word choices onto its specs.
Class AgenticProd.UI.Wizard Extends %RegisteredObject
{

Parameter AGENTPKG = "MyAI.Agent.";

Parameter POLICYPKG = "MyAI.Policy.";

Parameter TOOLPKG = "MyAI.Tools.";

/// Tokens a typical message costs, for the "about $x per message" figure (prompt, completion).
Parameter ESTPROMPT = 2500;

Parameter ESTCOMPLETION = 300;

/// A trial run never goes beyond this many tool rounds, whatever the agent's own limit.
Parameter RUNMAXSTEPS = 3;

Parameter PIDMESSAGE = "Patient identity is protected. Escalate instead.";

Parameter CUSTOMMESSAGE = "This call is blocked by a rule of this agent.";

/// class|title|text for the classes that ship with the project; others show their own description.
Parameter PLAIN = "AgenticProd.Tools.Base|Read the failed message and its errors|The message (patient fields hidden), the error log, similar past decisions;AgenticProd.Skill.HL7Repair|Repair HL7 v2 messages|Read segments, check the spec, prove a fix before proposing it;AgenticProd.Skill.CodeMapping|Map local codes to LOINC|Look up codes, search the LOINC knowledge base, past approved mappings";

/// tool|sentence for the trial run; {name} is filled from the call's arguments.
Parameter STEPTEXT = "get_failed_message|Read the failed message;get_error_events|Read the error log;get_similar_decisions|Looked at similar past decisions;get_segment|Read segment {segmentRef};search_interface_spec|Checked the interface spec for {topic};validate_fix|Tested a proposed fix;lookup_code|Looked up the code {localCode};search_loinc|Searched LOINC for {text};similar_past_mappings|Looked at past approved mappings";

// ---- options -------------------------------------------------------------------------------

/// Everything the wizard page needs to draw itself.
ClassMethod Options(pAdmin As %Boolean) As %DynamicObject
{
	Set tBase = ##class(AgenticProd.UI.Builder).Options(pAdmin)
	Set tOut = {"canEdit":(''pAdmin), "providers":[], "starters":(..Starters()), "abilities":(..Abilities(tBase)), "ready":(..ReadyQueries()), "samples":(..Samples()), "killSwitch":(..KillSwitch())}
	Set tIter = tBase.providers.%GetIterator()
	While tIter.%GetNext(, .tP) { Do tOut.providers.%Push({"name":(tP.name), "model":(tP.model), "price":(..PriceFor(tP.model))}) }
	// No Config Store entry yet: offer the key from .env that the triage agent uses
	If 'tOut.providers.%Size() {
		Set tDef = "AgenticProd.Agent.TriageAgent", tModel = $PARAMETER(tDef, "MODEL")
		Do tOut.providers.%Push({"name":"", "provider":($PARAMETER(tDef, "PROVIDER")), "apiKey":($PARAMETER(tDef, "APIKEY")), "model":(tModel), "price":(..PriceFor(tModel))})
	}
	Quit tOut
}

ClassMethod KillSwitch() As %Boolean
{
	Quit ''+##class(AgenticProd.UI.REST).AgentSetting(##class(AgenticProd.Eval.Runner).#AGENTITEM, "KillSwitch")
}

/// Dollars for a typical message on pModel, "" when the price table has no row.
ClassMethod PriceFor(pModel As %String) As %String
{
	Set tSC = ##class(AgenticProd.Data.PriceTable).Cost(pModel, ..#ESTPROMPT, ..#ESTCOMPLETION, 0, 0, .tCost)
	Quit $SELECT($$$ISOK(tSC): tCost, 1: "")
}

ClassMethod Starters() As %DynamicArray
{
	Quit [
		{"id":"fix", "title":"Fix failed messages", "text":"Find why a message failed and propose a fix. A person approves.", "icon":"first-aid-kit", "name":"Message fixer",
			"toolsets":["AgenticProd.Tools.Base"], "skills":["AgenticProd.Skill.HL7Repair","AgenticProd.Skill.CodeMapping"], "protectPid":true,
			"does":["Find why a message failed","Propose a fix; a person approves"],
			"instructions":("You look at messages that failed in this production."_$CHAR(10)_"1. Read the error first, then the message."_$CHAR(10)_"2. Load a skill when the error needs one."_$CHAR(10)_"3. Never change patient identity. If unsure, escalate."_$CHAR(10)_"Answer with one decision.")},
		{"id":"explain", "title":"Explain failures", "text":"Write a plain explanation for the support team. Changes nothing.", "icon":"message-question", "name":"Failure explainer",
			"toolsets":["AgenticProd.Tools.Base"], "skills":[], "protectPid":true,
			"does":["Explain in plain words why a message failed"],
			"instructions":("You explain why a message failed, for the support team."_$CHAR(10)_"1. Read the error, then the message."_$CHAR(10)_"2. Say what went wrong and what a person should check."_$CHAR(10)_"3. Do not propose to change the message.")},
		{"id":"scratch", "title":"Start from scratch", "text":"Your own instructions and abilities.", "icon":"pencil", "name":"My agent",
			"toolsets":[], "skills":[], "protectPid":false, "does":["Whatever your instructions say"], "instructions":""}
	]
}

/// Ready queries for the New ability panel: tested SELECTs on interoperability tables.
ClassMethod ReadyQueries() As %DynamicArray
{
	Quit [
		{"id":"newest", "label":"Newest messages sent to an item", "arg":"itemName", "example":"EhrOut", "tool":"get_recent_messages",
			"description":"Show the 5 newest messages sent to one production item, to see if it is up. itemName is the item's config name, e.g. EhrOut.",
			"sql":("SELECT TOP 5 ID, TimeCreated, SourceConfigName AS FromItem, %EXTERNAL(Status) AS Status"_$CHAR(10)_"FROM Ens.MessageHeader"_$CHAR(10)_"WHERE TargetConfigName = :itemName"_$CHAR(10)_"ORDER BY ID DESC")},
		{"id":"errors", "label":"Messages with errors for an item", "arg":"itemName", "example":"EhrOut", "tool":"get_recent_errors",
			"description":"Show the 5 newest messages for one production item that ended in an error, to see what keeps failing. itemName is the item's config name, e.g. EhrOut.",
			"sql":("SELECT TOP 5 ID, TimeCreated, SourceConfigName AS FromItem, %EXTERNAL(Status) AS Status"_$CHAR(10)_"FROM Ens.MessageHeader"_$CHAR(10)_"WHERE TargetConfigName = :itemName AND IsError = 1"_$CHAR(10)_"ORDER BY ID DESC")},
		{"id":"order", "label":"Earlier messages for the same order", "arg":"headerId", "example":"1", "tool":"get_earlier_messages",
			"description":"Show up to 10 earlier messages of the same session as one message, to see what happened to the order before. headerId is the message ID.",
			"sql":("SELECT TOP 10 m.ID, m.TimeCreated, m.SourceConfigName AS FromItem, m.TargetConfigName AS ToItem, %EXTERNAL(m.Status) AS Status"_$CHAR(10)_"FROM Ens.MessageHeader h JOIN Ens.MessageHeader m ON m.SessionId = h.SessionId AND m.ID < h.ID"_$CHAR(10)_"WHERE h.ID = :headerId"_$CHAR(10)_"ORDER BY m.ID DESC")}
	]
}

/// Newest recorded failures whose message still exists, for the Try step.
ClassMethod Samples() As %DynamicArray
{
	Set tOut = []
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 8 d.ID, d.Source, d.ErrorClass, d.ErrorText FROM AgenticProd_Data.DecisionLog d WHERE d.Namespace = ? AND EXISTS (SELECT 1 FROM Ens.MessageHeader h WHERE h.ID = d.HeaderId) ORDER BY d.ID DESC", $NAMESPACE)
		While tRS.%Next() {
			Do tOut.%Push({"id":(tRS.ID), "label":(tRS.Source_" · "_tRS.ErrorClass_" · "_$EXTRACT(tRS.ErrorText, 1, 60))})
		}
	} Catch {}
	Quit tOut
}

/// Toolsets and skills of this namespace in plain words, one row each.
ClassMethod Abilities(pBase As %DynamicObject) As %DynamicArray
{
	Set tOut = [], tWb = "AgenticProd.UI.Workbench"
	// A toolset that a skill carries is shown through the skill
	Set tViaSkill = ","
	Set tIter = pBase.skills.%GetIterator()
	While tIter.%GetNext(, .tS) {
		Set tTools = $PARAMETER(tS.class, "TOOLS")
		For i = 1:1:$LENGTH(tTools, ",") { Set tViaSkill = tViaSkill_$ZSTRIP($PIECE(tTools, ",", i), "<>W")_"," }
	}
	// ...unless an agent also lists it directly, like Tools.Base
	Set tDirect = ",", tIter = $CLASSMETHOD(tWb, "AgentClassesOf", "%AI.Agent").%GetIterator()
	While tIter.%GetNext(, .tA) { Set tDirect = tDirect_$TRANSLATE($PARAMETER(tA.class, "TOOLSETS"), " ", "")_"," }
	Set tIter = pBase.toolsets.%GetIterator()
	While tIter.%GetNext(, .tT) {
		Continue:((tViaSkill [ (","_tT.class_",")) && (tDirect '[ (","_tT.class_",")) && ($EXTRACT(tT.class, 1, 5) '= "MyAI."))
		Set tInfo = $CLASSMETHOD(tWb, "ToolSetInfo", tT.class)
		Do tOut.%Push(..AbilityRow(tT.class, "toolset", tInfo.name, tInfo.description, tT.tools))
	}
	Set tIter = pBase.skills.%GetIterator()
	While tIter.%GetNext(, .tS) {
		Set tInfo = $CLASSMETHOD(tWb, "SkillInfo", tS.class)
		Do tOut.%Push(..AbilityRow(tS.class, "skill", tInfo.name, tInfo.description, tS.tools))
	}
	Quit tOut
}

ClassMethod AbilityRow(pClass As %String, pKind As %String, pName As %String, pDesc As %String, pTools As %DynamicArray) As %DynamicObject [ Internal ]
{
	Set tTitle = pName, tText = pDesc
	For i = 1:1:$LENGTH(..#PLAIN, ";") {
		Set tRow = $PIECE(..#PLAIN, ";", i)
		If $PIECE(tRow, "|", 1) = pClass { Set tTitle = $PIECE(tRow, "|", 2), tText = $PIECE(tRow, "|", 3) }
	}
	Set tN = $SELECT($IsObject(pTools): pTools.%Size(), 1: 0)
	Quit {"class":(pClass), "kind":(pKind), "title":(tTitle), "text":(tText), "tech":(pClass_" · "_tN_" tool"_$SELECT(tN=1: "", 1: "s")), "mine":($EXTRACT(pClass, 1, 5) = "MyAI."), "tools":(pTools)}
}

// ---- compose -------------------------------------------------------------------------------

/// Class-name part from the agent's name: "Orders triage" gives OrdersTriage. "" when unusable.
ClassMethod IdOf(pName As %String) As %String
{
	Set tOut = "", tWord = ""
	For i = 1:1:$LENGTH(pName) + 1 {
		Set c = $EXTRACT(pName, i)
		If (c ?1AN) { Set tWord = tWord_c  Continue }
		Set:tWord'="" tOut = tOut_$ZCONVERT($EXTRACT(tWord), "U")_$EXTRACT(tWord, 2, *), tWord = ""
	}
	Quit:'(tOut ?1A.AN) ""
	Quit $EXTRACT(tOut, 1, 40)
}

/// Protect-identity rules: no read of PID, no fix step on PID-3, PID-5 or PID-7.
ClassMethod PidRules() As %DynamicArray [ Internal ]
{
	Set tRules = [{"arg":"segmentRef", "op":"starts with", "value":"PID"}]
	For tField = 3, 5, 7 {
		Do tRules.%Push({"arg":"fixJSON", "op":"contains", "value":("PID(1):"_tField)})
		Do tRules.%Push({"arg":"fixJSON", "op":"contains", "value":("PID:"_tField)})
	}
	Quit tRules
}

/// {"errors":[], "id", "agentClass", "policyClass", "parts":[{"kind","class","code"}], "agentSpec", "policySpec"}.
/// Nothing is written. The wizard spec: name, providerConfig, model, instructions, toolsets, skills and
/// rules {protectPid, audit, custom:[{arg,op,value}], maxSteps, dailyBudget}.
ClassMethod Compose(pSpec As %DynamicObject) As %DynamicObject
{
	Set tOut = {"errors":[], "parts":[], "id":"", "agentClass":"", "policyClass":""}
	If '$IsObject(pSpec) { Do tOut.errors.%Push("The form is empty.")  Quit tOut }
	Set tB = "AgenticProd.UI.Builder"
	Set tName = $CLASSMETHOD(tB, "Str", pSpec, "name"), tId = ..IdOf(tName)
	If (tId = "") || ($LENGTH(tId) < 2) { Do tOut.errors.%Push("Give the agent a name that starts with a letter, like Orders triage.")  Quit tOut }
	Set tOut.id = tId, tOut.agentClass = ..#AGENTPKG_tId, tOut.policyClass = ..#POLICYPKG_tId_"Rules"
	Set tRulesIn = pSpec.%Get("rules")
	If '$IsObject(tRulesIn) Set tRulesIn = {}

	// Rules become one policy class; with no rules the read-only policy of the project applies as it is
	Set tPolicyRules = []
	Do:tRulesIn.%Get("protectPid") ..AppendAll(tPolicyRules, ..PidRules())
	Set tCustom = $CLASSMETHOD(tB, "Rows", tRulesIn, "custom"), tIter = tCustom.%GetIterator()
	While tIter.%GetNext(, .tR) {
		Continue:'$IsObject(tR)
		Do tPolicyRules.%Push({"arg":($CLASSMETHOD(tB, "Str", tR, "arg")), "op":($CLASSMETHOD(tB, "Str", tR, "op")), "value":($CLASSMETHOD(tB, "Str", tR, "value"))})
	}
	Set tHasPolicy = tPolicyRules.%Size() > 0
	Set tMessage = $SELECT(tRulesIn.%Get("protectPid"): ..#PIDMESSAGE, 1: ..#CUSTOMMESSAGE)
	Set tPolicySpec = {"kind":"policy", "class":(tOut.policyClass), "tools":[], "message":(tMessage), "rules":(tPolicyRules)}
	Set tAgentSpec = {"kind":"agent", "class":(tOut.agentClass), "providerConfig":(pSpec.%Get("providerConfig")), "provider":(pSpec.%Get("provider")), "apiKey":(pSpec.%Get("apiKey")), "model":(pSpec.%Get("model")),
		"toolsets":(pSpec.%Get("toolsets")), "skills":(pSpec.%Get("skills")), "instructions":(pSpec.%Get("instructions")),
		"authPolicy":"AgenticProd.Policy.ReadOnly", "auditPolicy":($SELECT(tRulesIn.%Get("audit"): "AgenticProd.Policy.Audit", 1: "")),
		"maxSteps":(+tRulesIn.%Get("maxSteps")), "dailyBudget":(+tRulesIn.%Get("dailyBudget"))}
	Set tOut.agentSpec = tAgentSpec, tOut.policySpec = $SELECT(tHasPolicy: tPolicySpec, 1: "")

	If tHasPolicy {
		Set tGen = $CLASSMETHOD(tB, "Generate", "policy", tPolicySpec)
		Do ..AddErrors(tOut.errors, tGen.errors)
		Do:tGen.code'="" tOut.parts.%Push({"kind":"policy", "class":(tOut.policyClass), "code":(tGen.code)})
	}
	// The policy class does not exist yet, so the agent is checked against the read-only policy
	// and its AUTHPOLICY line is pointed at the generated class afterwards
	Set tGen = $CLASSMETHOD(tB, "Generate", "agent", tAgentSpec)
	Do ..AddErrors(tOut.errors, tGen.errors)
	If tGen.code '= "" {
		Set tCode = tGen.code
		Set:tHasPolicy tCode = $REPLACE(tCode, "Parameter AUTHPOLICY = ""AgenticProd.Policy.ReadOnly""", "Parameter AUTHPOLICY = """_tOut.policyClass_"""")
		Do tOut.parts.%Push({"kind":"agent", "class":(tOut.agentClass), "code":(tCode)})
	}
	Quit tOut
}

ClassMethod AppendAll(pTo As %DynamicArray, pFrom As %DynamicArray) [ Internal ]
{
	Set tIter = pFrom.%GetIterator()
	While tIter.%GetNext(, .tItem) { Do pTo.%Push(tItem) }
}

ClassMethod AddErrors(pTo As %DynamicArray, pFrom As %DynamicArray) [ Internal ]
{
	Do ..AppendAll(pTo, pFrom)
}

// ---- save ----------------------------------------------------------------------------------

/// Saves the policy (when there are rules) and then the agent; both compile first as scratch copies
/// inside Builder.Save. {"ok","saved","errors","classes":[]}.
ClassMethod Save(pSpec As %DynamicObject) As %DynamicObject
{
	Set tCompose = ..Compose(pSpec)
	Set tOut = {"ok":0, "saved":0, "errors":(tCompose.errors), "classes":[]}
	Quit:tOut.errors.%Size() tOut
	Set tB = "AgenticProd.UI.Builder"
	If $IsObject(tCompose.policySpec) {
		Set tRes = $CLASSMETHOD(tB, "Save", "policy", tCompose.policySpec)
		If 'tRes.saved { Do ..AppendAll(tOut.errors, tRes.errors)  Quit tOut }
		Do tOut.classes.%Push(tRes.class)
	}
	Set tAgentSpec = tCompose.agentSpec
	Set:$IsObject(tCompose.policySpec) tAgentSpec.authPolicy = tCompose.policyClass
	Set tRes = $CLASSMETHOD(tB, "Save", "agent", tAgentSpec)
	If 'tRes.saved { Do ..AppendAll(tOut.errors, tRes.errors)  Quit tOut }
	Do tOut.classes.%Push(tRes.class)
	Set tOut.ok = 1, tOut.saved = 1
	Quit tOut
}

// ---- trial run -----------------------------------------------------------------------------

/// {"state":"ok"|"needs-confirm"|"blocked"|"invalid"|"failed", ...} (not "status": Handle puts the HTTP status there). Needs pConfirm for a live call. A process-private
/// stub (^||AgenticProd.WizardStub, JSON {"toolCalls":[...],"answer":"","promptTokens":0,
/// "completionTokens":0}) replaces the model call, so tests never reach an LLM.
ClassMethod Run(pSpec As %DynamicObject, pSampleId As %Integer, pConfirm As %Boolean) As %DynamicObject
{
	Set tCompose = ..Compose(pSpec)
	Quit:tCompose.errors.%Size() {"state":"invalid", "errors":(tCompose.errors)}
	If ..KillSwitch() Quit {"state":"blocked", "reason":"The AI kill switch is on. Turn it off on the Settings tab to run the agent."}
	Set tStub = $GET(^||AgenticProd.WizardStub)
	If tStub = "" {
		Set tNoLLM = ##class(AgenticProd.Operation.Agent).TestRunActive()
		Quit:tNoLLM {"state":"blocked", "reason":"A unit test run is active: no AI call is made."}
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT HeaderId, SessionId, Source, Format, ErrorText, ErrorClass FROM AgenticProd_Data.DecisionLog WHERE ID = ?", +pSampleId)
	If 'tRS.%Next() Quit {"state":"invalid", "errors":["Pick a sample message."]}
	Set tPrice = ..PriceFor(pSpec.%Get("model"))
	If 'pConfirm Quit {"state":"needs-confirm", "price":(tPrice), "model":(pSpec.%Get("model"))}

	Set tOut = {"state":"ok", "steps":[], "answer":"", "decision":"", "costUsd":0, "ms":0, "promptTokens":0, "completionTokens":0}
	Set tStart = $ZHOROLOG
	Try {
		If tStub '= "" {
			Set tRun = {}.%FromJSON(tStub)
		} Else {
			Set tRun = ..RunLive(tCompose, pSpec, tRS)
		}
		Do ..FillSteps(tOut, tRun.toolCalls, tRun.answer)
		Set tOut.promptTokens = +tRun.promptTokens, tOut.completionTokens = +tRun.completionTokens
		Set tSC = ##class(AgenticProd.Data.PriceTable).Cost(pSpec.%Get("model"), tOut.promptTokens, tOut.completionTokens, 0, 0, .tCost)
		Set tOut.costUsd = $SELECT($$$ISOK(tSC): +tCost, 1: 0)
	} Catch ex {
		Set tOut.state = "failed", tOut.error = ex.DisplayString()
	}
	Set tOut.ms = ($ZHOROLOG - tStart) * 1000 \ 1
	Quit tOut
}

/// The one real model call: scratch copies of the policy and agent, one Chat with at most
/// RUNMAXSTEPS tool rounds. {"toolCalls":[...],"answer","promptTokens","completionTokens"}.
ClassMethod RunLive(pCompose As %DynamicObject, pSpec As %DynamicObject, pSample As %SQL.StatementResult) As %DynamicObject [ Internal ]
{
	Set tB = "AgenticProd.UI.Builder", tAgentTemp = $CLASSMETHOD(tB, "TempName"), tPolTemp = ""
	Try {
		Set tAgentSpec = pCompose.agentSpec
		If $IsObject(pCompose.policySpec) {
			Set tPolTemp = $CLASSMETHOD(tB, "TempName")
			$$$ThrowOnError($CLASSMETHOD(tB, "CompileScratch", "policy", pCompose.policySpec, tPolTemp))
			Set tAgentSpec.authPolicy = tPolTemp
		}
		$$$ThrowOnError($CLASSMETHOD(tB, "CompileScratch", "agent", tAgentSpec, tAgentTemp))

		Set tAgent = $CLASSMETHOD(tAgentTemp, "%New")
		Set tAgent.ProviderConfig = pSpec.%Get("providerConfig")
		Set tAgent.Model = pSpec.%Get("model")
		$$$ThrowOnError(tAgent.%Init())
		Set tAgent.MaxIterations = $SELECT(+tAgent.MaxIterations && (tAgent.MaxIterations < ..#RUNMAXSTEPS): tAgent.MaxIterations, 1: ..#RUNMAXSTEPS)
		Set tSession = tAgent.CreateSession({"max_iterations":(..#RUNMAXSTEPS), "cache":{"enabled":1, "cache_system_prompt":1, "cache_tool_definitions":1}})
		$$$ThrowOnError(tSession.%Save())
		// Audit rows are how the steps are listed afterwards, denied calls included
		Set tAudit = ##class(AgenticProd.Policy.Audit).%New()
		Set tAudit.HeaderId = pSample.HeaderId, tAudit.AgentSessionId = tSession.%Id()
		$$$ThrowOnError(tAgent.ToolManager.SetAuditPolicy(tAudit))

		Set tReq = ##class(AgenticProd.Msg.TriageRequest).%New()
		Set tReq.HeaderId = pSample.HeaderId, tReq.SessionId = pSample.SessionId, tReq.Source = pSample.Source
		Set tReq.Format = pSample.Format, tReq.ErrorText = pSample.ErrorText, tReq.ErrorClass = pSample.ErrorClass
		Set tAnswer = ""
		Try {
			Set tAnswer = tAgent.Chat(tSession, ##class(AgenticProd.Operation.Agent).BuildTask(tReq)).Content
		} Catch exChat {
			Set tAnswer = "The agent stopped: "_exChat.DisplayString()
		}
		$$$ThrowOnError(tSession.%Save())
		Set tStats = tSession.GetStats()
		Set tRun = {"toolCalls":[], "answer":(tAnswer), "promptTokens":(+tStats."total_prompt_tokens"), "completionTokens":(+tStats."total_completion_tokens")}
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, Arguments, Status, ErrorText, DurationMs FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? ORDER BY ID", tSession.%Id())
		While tRS.%Next() {
			Do tRun.toolCalls.%Push({"tool":(tRS.Tool), "arguments":(tRS.Arguments), "status":(tRS.Status), "error":(tRS.ErrorText), "ms":(+tRS.DurationMs)})
		}
	} Catch ex {
		Do $CLASSMETHOD(tB, "DropScratch", tAgentTemp)
		Do:tPolTemp'="" $CLASSMETHOD(tB, "DropScratch", tPolTemp)
		Throw ex
	}
	Do $CLASSMETHOD(tB, "DropScratch", tAgentTemp)
	Do:tPolTemp'="" $CLASSMETHOD(tB, "DropScratch", tPolTemp)
	Quit tRun
}

/// Tool calls and the final answer as sentences: {"kind":"read"|"blocked"|"failed","text","detail"}
/// and a last {"kind":"answer"} step.
ClassMethod FillSteps(pOut As %DynamicObject, pCalls As %DynamicArray, pAnswer As %String) [ Internal ]
{
	Set tIter = pCalls.%GetIterator()
	While tIter.%GetNext(, .tCall) {
		Set tText = ..StepText(tCall.tool, tCall.arguments)
		If tCall.status = "DENIED" {
			Do pOut.steps.%Push({"kind":"blocked", "text":("Tried: "_tText), "detail":(tCall.error)})
		} ElseIf tCall.status = "OK" {
			Do pOut.steps.%Push({"kind":"read", "text":(tText), "detail":""})
		} Else {
			Do pOut.steps.%Push({"kind":"failed", "text":(tText), "detail":(tCall.error)})
		}
	}
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(pAnswer, .tDecision)
	If $$$ISOK(tSC) {
		Set pOut.decision = tDecision.Decision
		Do pOut.steps.%Push({"kind":"answer", "text":("Decision: "_tDecision.Decision_" · confidence "_tDecision.Confidence), "detail":(tDecision.Reason)})
	} Else {
		Do pOut.steps.%Push({"kind":"answer", "text":"The agent answered", "detail":($EXTRACT(pAnswer, 1, 400))})
	}
	Set pOut.answer = $EXTRACT(pAnswer, 1, 2000)
}

/// "Read segment OBX(1)" from the tool name and its arguments JSON.
ClassMethod StepText(pTool As %String, pArgs As %String) As %String [ Internal ]
{
	Try { Set tArgs = {}.%FromJSON(pArgs) } Catch { Set tArgs = {} }
	Set tText = ""
	For i = 1:1:$LENGTH(..#STEPTEXT, ";") {
		Set tRow = $PIECE(..#STEPTEXT, ";", i)
		Set:($PIECE(tRow, "|", 1) = pTool) tText = $PIECE(tRow, "|", 2)
	}
	If tText = "" {
		// A tool of the user's own: "get_recent_messages" with itemName = EhrOut
		Set tText = "Ran "_$TRANSLATE(pTool, "_", " ")
		Set tList = "", tIter = tArgs.%GetIterator()
		While tIter.%GetNext(.tKey, .tVal) { Set tList = tList_$SELECT(tList="": "", 1: ", ")_tKey_" = "_$SELECT($IsObject(tVal): tVal.%ToJSON(), 1: tVal) }
		Quit tText_$SELECT(tList="": "", 1: " ("_tList_")")
	}
	Set tIter = tArgs.%GetIterator()
	While tIter.%GetNext(.tKey, .tVal) { Set tText = $REPLACE(tText, "{"_tKey_"}", $SELECT($IsObject(tVal): "", 1: tVal)) }
	// A placeholder the call did not fill
	While tText [ "{" { Set tText = $PIECE(tText, "{", 1)_$PIECE($PIECE(tText, "{", 2, *), "}", 2, *) }
	Quit $ZSTRIP(tText, "<>W")
}

// ---- REST entry ----------------------------------------------------------------------------

/// {"status":200|400|403, ...body}. pAction: compose (anyone), save and run (administrators).
ClassMethod Handle(pAction As %String, pBody As %DynamicObject, pAdmin As %Boolean) As %DynamicObject
{
	Set tSpec = pBody.%Get("spec")
	If '$IsObject(tSpec) Quit {"status":400, "error":"spec must be an object"}
	If (pAction '= "compose") && 'pAdmin Quit {"status":403, "error":"Saving and running agents is for administrators."}
	Set tRes = ""
	If pAction = "compose" { Set tRes = ..Compose(tSpec) }
	ElseIf pAction = "save" { Set tRes = ..Save(tSpec) }
	ElseIf pAction = "run" { Set tRes = ..Run(tSpec, pBody.%Get("sample"), ''pBody.%Get("confirm")) }
	If '$IsObject(tRes) Quit {"status":400, "error":"unknown action"}
	Do tRes.%Set("status", 200, "number")
	Quit tRes
}

}
