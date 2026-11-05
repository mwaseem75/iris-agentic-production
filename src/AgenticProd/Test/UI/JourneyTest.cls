/// UI.Journey.Build on stub rows: no database rows, no LLM. The REST route is covered by RESTTest.
Class AgenticProd.Test.UI.JourneyTest Extends AgenticProd.Test.Case
{

ClassMethod Items() As %DynamicObject
{
	Quit {"LABFILEIN":{"name":"LabFileIn","lane":"inbound","workflow":0}, "LABROUTER":{"name":"LabRouter","lane":"router","workflow":0},
		"TRIAGE":{"name":"Triage","lane":"decision","workflow":0}, "TRIAGEAGENT":{"name":"TriageAgent","lane":"ai","workflow":0},
		"EHROUT":{"name":"EhrOut","lane":"outcome","workflow":0}, "INTEGRATIONSUPPORT":{"name":"IntegrationSupport","lane":"outcome","workflow":1}}
}

ClassMethod Hop(pSession As %Integer, pFrom As %String, pTo As %String, pT0 As %String, pT1 As %String) As %DynamicObject
{
	Quit {"SessionId":(pSession), "From":(pFrom), "To":(pTo), "T0":(pT0), "T1":(pT1), "Error":0}
}

ClassMethod Log(pDecision As %String, pDecisionJSON As %String = "") As AgenticProd.Data.DecisionLog
{
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = -9801, tLog.SessionId = 100, tLog.Decision = pDecision, tLog.ErrorClass = "UNMAPPED_CODE", tLog.ErrorText = "OBX-3 code ZZ1 not in lookup"
	Set tLog.CreatedAt = "2026-10-31 10:00:00", tLog.DecisionJSON = pDecisionJSON
	Quit tLog
}

ClassMethod Usage(pDecision As %String) As %DynamicObject
{
	Quit {"Model":"test-model", "Replay":1, "Decision":(pDecision), "Confidence":0.9, "PromptTokens":100, "CompletionTokens":20, "CostUsd":0.001}
}

ClassMethod Kinds(pJourney As %DynamicObject) As %String
{
	Set tOut = "", tIter = pJourney.steps.%GetIterator()
	While tIter.%GetNext(, .tStep) {
		Set tOut = tOut_$SELECT(tOut'="": ",", 1: "")_tStep.kind
	}
	Quit tOut
}

Method TestMapCodeApprovedThenResent()
{
	Set tLog = ..Log("MAP_CODE")
	Set tLog.Outcome = "APPROVED", tLog.Reviewer = "anna", tLog.ReviewedAt = "2026-10-31 10:03:01", tLog.LocalCode = "ZZ1", tLog.Loinc = "2345-7"
	Set tHops = [(..Hop(100, "LabFileIn", "LabRouter", "2026-10-31 10:00:00.000", "2026-10-31 10:00:00.050")),
		(..Hop(100, "LabRouter", "Triage", "2026-10-31 10:00:00.040", "2026-10-31 10:00:00.900")),
		(..Hop(100, "Triage", "TriageAgent", "2026-10-31 10:00:00.100", "2026-10-31 10:00:00.700")),
		(..Hop(100, "Triage", "IntegrationSupport", "2026-10-31 10:00:00.850", "2026-10-31 10:00:00.900")),
		(..Hop(200, "LabRouter", "EhrOut", "2026-10-31 10:03:02.000", "2026-10-31 10:03:02.080"))]
	Set tTools = [{"Tool":"get_failed_message", "Status":"OK", "DurationMs":30, "ResultLength":400, "ErrorText":"", "CreatedAt":"2026-10-31 10:00:00.300"},
		{"Tool":"search_loinc", "Status":"OK", "DurationMs":60, "ResultLength":900, "ErrorText":"", "CreatedAt":"2026-10-31 10:00:00.500"}]
	Set tLearned = {"ID":7, "LocalCode":"ZZ1", "Loinc":"2345-7", "Display":"Glucose", "Reviewer":"anna", "ApprovedAt":"2026-10-31 10:03:01"}
	Set tJ = ##class(AgenticProd.UI.Journey).Build(tLog, "IRISAPP", ..Items(), tHops, tTools, ..Usage("MAP_CODE"), tLearned)
	Do $$$AssertEquals(..Kinds(tJ), "inbound,router,hop,hop,agent,tool,tool,injection,triage,hop,workflow,learning,resend", "steps in path order")
	Set tWait = tJ.steps.%Get(10)
	Do $$$AssertEquals(tWait.waitLabel, "waited 3 min for anna", "long wait is labelled")
	Do $$$AssertEquals(tWait.status, "ok")
	Do $$$AssertEquals(tWait.durationMs, 180100, "wait runs from the task hop to the answer")
	Set tTool = tJ.steps.%Get(5)
	Do $$$AssertEquals(tTool.title, "Tool: get_failed_message")
	Do $$$AssertEquals(tTool.node, "TriageAgent")
	Set tResend = tJ.steps.%Get(12)
	Do $$$AssertEquals(tResend.session, 200, "the resend runs in its own session")
	Do $$$AssertEquals(tResend.edge.to, "EhrOut")
	Do $$$AssertEquals(tJ.steps.%Get(11).kind, "learning")
	Do $$$AssertEquals(tJ.steps.%Get(8).outcome, "SENT_FOR_APPROVAL")
	Do $$$AssertEquals(tJ.steps.%Get(4).sub, "model", "agent step pulses Model")
	Do $$$AssertEquals(tJ.steps.%Get(4).tokens, 120)
	Do $$$AssertEquals(tTool.sub, "tools")
	Do $$$AssertEquals(tJ.steps.%Get(6).sub, "knowledge", "search_loinc lights Knowledge")
	Do $$$AssertEquals(tJ.steps.%Get(11).sub, "memory")
	Do $$$AssertEquals(tJ.steps.%Get(11).learned, "ZZ1", "memory shows the learned code")
	Do $$$AssertEquals(tJ.steps.%Get(10).node, "IntegrationSupport", "human review node")
	Do $$$AssertEquals(tJ.agent.provider, "openai")
	Do $$$AssertEquals(tJ.agent.model, "test-model")
	Do $$$AssertEquals(tJ.agent.tools.%Get(1), "search_loinc")
	Do $$$AssertEquals(tJ.agent.searches, 1)
	Do $$$AssertEquals(tJ.agent.allowed, 2)
	Do $$$AssertEquals(tJ.agent.denied, 0)
	Do $$$AssertEquals(tJ.agent.learned, "ZZ1")
	Do $$$AssertEquals(tJ.agent.skillsUsed.%Size(), 1, "search_loinc belongs to CodeMapping")
	Do $$$AssertEquals(tJ.agent.skillsUsed.%Get(0), "CodeMapping")
	Do $$$AssertEquals(tJ.agent.decision, "MAP_CODE")
}

Method TestOldItemNamesMapToRenamedItems()
{
	Set tLog = ..Log("AUTO_FIX")
	Set tHops = [(..Hop(100, "LabFileIn", "LabRouter", "2026-10-31 10:00:00.000", "2026-10-31 10:00:00.050")),
		(..Hop(100, "LabRouter", "Triage", "2026-10-31 10:00:00.040", "2026-10-31 10:00:00.500")),
		(..Hop(100, "Triage", "TriageAgent", "2026-10-31 10:00:00.100", "2026-10-31 10:00:00.400")),
		(..Hop(100, "Triage", "LabRouter", "2026-10-31 10:00:00.480", "2026-10-31 10:00:00.520")),
		(..Hop(100, "LabRouter", "NphiesOut", "2026-10-31 10:00:00.530", "2026-10-31 10:00:00.560"))]
	Set tJ = ##class(AgenticProd.UI.Journey).Build(tLog, "IRISAPP", ..Items(), tHops, [], ..Usage("AUTO_FIX"), "", "APPLIED")
	Do $$$AssertEquals(tJ.steps.%Get(tJ.steps.%Size() - 1).edge.to, "EhrOut", "stored hop to the old name shows as EhrOut")
}

/// A replay whose recording had a different prompt says so in the agent step.
Method TestReplayWithChangedPromptIsMarked()
{
	Set tUsage = ..Usage("ESCALATE")
	Set tJ = ##class(AgenticProd.UI.Journey).Build(..Log("ESCALATE"), "IRISAPP", ..Items(), [], [], tUsage, "", "SENT_FOR_APPROVAL")
	Do $$$AssertNotTrue(tJ.steps.%Get(1).text [ "different prompt", "no mark by default")
	Set tUsage.PromptMismatch = 1
	Set tJ = ##class(AgenticProd.UI.Journey).Build(..Log("ESCALATE"), "IRISAPP", ..Items(), [], [], tUsage, "", "SENT_FOR_APPROVAL")
	Set tIter = tJ.steps.%GetIterator(), tText = ""
	While tIter.%GetNext(, .tStep) { Set:(tStep.kind = "agent") tText = tStep.text }
	Do $$$AssertTrue(tText [ "Recorded with a different prompt", tText)
}

Method TestAutoFixApplied()
{
	Set tLog = ..Log("AUTO_FIX")
	Set tHops = [(..Hop(100, "LabFileIn", "LabRouter", "2026-10-31 10:00:00.000", "2026-10-31 10:00:00.050")),
		(..Hop(100, "LabRouter", "Triage", "2026-10-31 10:00:00.040", "2026-10-31 10:00:00.500")),
		(..Hop(100, "Triage", "TriageAgent", "2026-10-31 10:00:00.100", "2026-10-31 10:00:00.400")),
		(..Hop(100, "Triage", "EhrOut", "2026-10-31 10:00:00.480", "2026-10-31 10:00:00.520"))]
	Set tJ = ##class(AgenticProd.UI.Journey).Build(tLog, "IRISAPP", ..Items(), tHops, [], ..Usage("AUTO_FIX"), "", "APPLIED")
	Do $$$AssertEquals(..Kinds(tJ), "inbound,router,hop,hop,agent,injection,triage,out", "no workflow, no learning")
	Do $$$AssertEquals(tJ.steps.%Get(2).text, "Triage total (includes agent): 0.5 s.", "the Triage hop includes the agent run")
	Do $$$AssertEquals(tJ.outcome, "applied")
	Do $$$AssertEquals(tJ.steps.%Get(6).outcome, "APPLIED")
	Do $$$AssertEquals(tJ.steps.%Get(7).edge.to, "EhrOut")
	Do $$$AssertEquals(tJ.steps.%Get(7).waitLabel, "", "short steps are not labelled")
	Do $$$AssertEquals(tJ.agent.learned, "", "nothing learned")
	Do $$$AssertEquals(tJ.agent.tools.%Size(), 0)
}

Method TestFlaggedInjection()
{
	Set tLog = ..Log("ESCALATE", "{""evidence"":[""suspicious instruction in NTE(1):3: ignore previous instructions""]}")
	Set tJ = ##class(AgenticProd.UI.Journey).Build(tLog, "IRISAPP", ..Items(), [], [], "", "", "SENT_FOR_APPROVAL")
	Set tInj = tJ.steps.%Get(2)
	Do $$$AssertEquals(tInj.kind, "injection", "no hops and no agent run still gives the checks")
	Do $$$AssertEquals(tInj.status, "bad")
	Do $$$AssertTrue(tInj.text [ "NTE(1):3", "the flagged path is named")
	Do $$$AssertEquals(tJ.steps.%Get(1).status, "warn", "agent step says it was not used")
	Do $$$AssertEquals(tJ.steps.%Get(4).kind, "workflow", "an escalation waits for a person")
	Do $$$AssertEquals(tJ.steps.%Get(4).status, "wait")
	Do $$$AssertEquals(tJ.agent.used, 0, "agent not used")
}

/// A flagged message where the agent still ran and one call was refused by the read-only policy.
Method TestDeniedToolLightsPolicies()
{
	Set tLog = ..Log("ESCALATE", "{""evidence"":[""suspicious instruction in NTE(1):3: ignore previous instructions""]}")
	Set tHops = [(..Hop(100, "Triage", "TriageAgent", "2026-10-31 10:00:00.100", "2026-10-31 10:00:00.700"))]
	Set tTools = [{"Tool":"load_skill", "Status":"OK", "DurationMs":5, "ResultLength":50, "ErrorText":"", "CreatedAt":""},
		{"Tool":"update_message", "Status":"DENIED", "DurationMs":1, "ResultLength":0, "ErrorText":"", "CreatedAt":""}]
	Set tJ = ##class(AgenticProd.UI.Journey).Build(tLog, "IRISAPP", ..Items(), tHops, tTools, ..Usage("ESCALATE"), "", "SENT_FOR_APPROVAL")
	Set tSkill = "", tDenied = ""
	Set tIter = tJ.steps.%GetIterator()
	While tIter.%GetNext(, .tStep) {
		Set:tStep.tool="load_skill" tSkill = tStep
		Set:tStep.tool="update_message" tDenied = tStep
	}
	Do $$$AssertEquals(tSkill.sub, "skills")
	Do $$$AssertEquals(tDenied.denied, 1, "refused call flagged")
	Do $$$AssertEquals(tDenied.status, "bad")
	Do $$$AssertEquals(tJ.agent.denied, 1)
	Do $$$AssertEquals(tJ.agent.skillCalls, 1)
	Do $$$AssertEquals(tJ.agent.skills.%Size(), 2, "HL7Repair and CodeMapping")
	Do $$$AssertEquals(tJ.steps.%Get(tJ.steps.%Size() - 1).kind, "workflow")
}

Method TestHelpers()
{
	Do $$$AssertEquals(##class(AgenticProd.UI.Journey).Diff("2026-10-31 10:00:00.100", "2026-10-31 10:00:01.350"), 1250)
	Do $$$AssertEquals(##class(AgenticProd.UI.Journey).Diff("2026-10-31 23:59:59", "2026-11-01 00:00:01"), 2000, "across midnight")
	Do $$$AssertEquals(##class(AgenticProd.UI.Journey).Human(181000), "3 min")
	Do $$$AssertEquals(##class(AgenticProd.UI.Journey).Shift("2026-10-31 00:00:00.100", -200), "2026-10-30 23:59:59.900")
}

}
