Include Ensemble

/// The path of one message for the Flow tab's journey mode: ordered steps built from real rows
/// (hops, decision, tool calls, usage, workflow answer, learned mapping), following the message into
/// the sessions its resend starts. Reads only. Get gathers the rows, Build turns them into steps and
/// takes plain input so the tests can feed it stubs.
Class AgenticProd.UI.Journey Extends %RegisteredObject
{

/// A pause longer than this is compressed in the player and labelled with its real length.
Parameter LONGWAITMS = 20000;

/// Steps for decision pId of pNs, or "" when there is no such decision.
ClassMethod Get(pNs As %String, pId As %String) As %DynamicObject
{
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Quit:(pId'?1.N)||'##class(AgenticProd.Data.DecisionLog).%ExistsId(pId) ""
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pId)
	Set tSpan = ##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 Attributes FROM AgenticProd_Data.Span WHERE HeaderId = ? AND Namespace = ? AND Name = 'triage decision' ORDER BY ID DESC", tLog.HeaderId, pNs).%Get(0)
	Set tSpanOutcome = $SELECT($IsObject(tSpan)&&(tSpan.Attributes '= ""): ##class(%DynamicObject).%FromJSON(tSpan.Attributes).%Get("agentic.final_outcome"), 1: "")
	Set tUsage = ##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 PromptMismatch, Model, Replay, Decision, Confidence, AgentSessionId, PromptTokens, CompletionTokens, CostUsd, DecisionJSON FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND Namespace = ? ORDER BY ID DESC", tLog.HeaderId, pNs).%Get(0)
	Set tTools = $SELECT($IsObject(tUsage)&&(tUsage.AgentSessionId '= ""): ##class(AgenticProd.UI.REST).Rows("SELECT Tool, Status, DurationMs, ResultLength, ErrorText, CreatedAt FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? ORDER BY ID", tUsage.AgentSessionId, pNs), 1: [])
	Set tLearned = ##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 ID, LocalCode, Loinc, Display, Reviewer, ApprovedAt FROM AgenticProd_Data.LearnedMapping WHERE DecisionLogId = ? AND Origin = 'Approved' ORDER BY ID DESC", pId).%Get(0)
	Set tMessage = ##class(AgenticProd.UI.REST).MaskedMessage(tLog.HeaderId, .tSecrets, pNs)
	Quit ..Build(tLog, pNs, ..Items(), ..Hops(tLog.SessionId, ..TriageSessions(tLog.HeaderId)), tTools, tUsage, tLearned, tSpanOutcome, .tSecrets)
}

/// Items of the running production by upper-case name: {name, lane, workflow}. Header names and item
/// names are matched without case.
ClassMethod Items() As %DynamicObject
{
	Set tItems = {}
	Set tName = ##class(Ens.Director).GetActiveProductionName()
	Set:tName="" tName = $GET(^Ens.Configuration("csp", "LastProduction"))
	Set tProd = $SELECT(tName'="": ##class(Ens.Config.Production).%OpenId(tName), 1: "")
	Quit:'$IsObject(tProd) tItems
	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i), tClass = tItem.ClassName
		Set tWorkflow = ##class(%Dictionary.CompiledClass).%ExistsId(tClass) && $CLASSMETHOD(tClass, "%IsA", "EnsLib.Workflow.Operation")
		Set tAgentCls = ""
		Do:(tClass = "AgenticProd.Operation.Agent") tItem.GetSetting("AgentClass", .tAgentCls)
		// GetSetting leaves the output undefined when the item has no such setting
		Set:'$DATA(tAgentCls) tAgentCls = ""
		Do tItems.%Set($ZCONVERT(tItem.Name, "U"), {"name":(tItem.Name), "lane":(##class(AgenticProd.UI.Flow).Lane(tClass)), "workflow":(''tWorkflow), "agentClass":(tAgentCls)})
	}
	Quit tItems
}

/// Sessions in which a Sentinel (plug-in or Add to production) handed the failed header pHeaderId to Triage.
/// Triage's own messages run there, not in the failed message's session.
ClassMethod TriageSessions(pHeaderId As %Integer) As %String
{
	Set tOut = ""
	Quit:pHeaderId="" tOut
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT SessionId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'AgenticProd.Msg.TriageRequest' AND MessageBodyId IN (SELECT ID FROM AgenticProd_Msg.TriageRequest WHERE HeaderId = ?)", pHeaderId)
	While tRS.%Next() { Set:tRS.SessionId'="" tOut = tOut_$SELECT(tOut'="": ",", 1: "")_tRS.SessionId }
	Quit tOut
}

/// Request hops of the message's session and of the sessions its resends started, in header order.
/// pExtra: comma list of further sessions (TriageSessions); their hops are marked triage.
ClassMethod Hops(pSessionId As %Integer, pExtra As %String = "") As %DynamicArray
{
	Quit:pSessionId="" []
	Set tSessions = pSessionId
	For i = 1:1:$LENGTH(pExtra, ",") {
		Set tX = $PIECE(pExtra, ",", i)
		Set:(tX'="")&&(tX'=pSessionId) tSessions = tSessions_","_tX, tExtra(tX) = ""
	}
	// a resent copy may start its own session; Resent on the original points to it
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT SessionId FROM Ens.MessageHeader WHERE ID IN (SELECT Resent FROM Ens.MessageHeader WHERE SessionId = ? AND Resent > 0) OR SuperSession = ?", pSessionId, pSessionId)
	While tRS.%Next() {
		Set:(tRS.SessionId'="")&&((","_tSessions_",")'[(","_tRS.SessionId_",")) tSessions = tSessions_","_tRS.SessionId
	}
	Set tHops = ##class(AgenticProd.UI.REST).Rows("SELECT ID, SessionId, SourceConfigName AS ""From"", TargetConfigName AS ""To"", TimeCreated AS T0, TimeProcessed AS T1, IsError AS Error, %EXTERNAL(Status) AS St FROM Ens.MessageHeader"
		_" WHERE Type = 1 AND SessionId IN ("_tSessions_") AND NOT SourceConfigName %STARTSWITH 'Ens.' AND NOT TargetConfigName %STARTSWITH 'Ens.' ORDER BY ID")
	Set tIter = tHops.%GetIterator()
	While tIter.%GetNext(, .tHop) { Do:$DATA(tExtra(tHop.SessionId)) tHop.%Set("triage", 1, "number") }
	Quit tHops
}

/// Milliseconds from UTC timestamp pA to pB; "" when either is empty.
ClassMethod Diff(pA As %String, pB As %String) As %Integer
{
	Quit:(pA="")||(pB="") ""
	Set tA = $ZDATETIMEH(pA, 3), tB = $ZDATETIMEH(pB, 3)
	Quit ((+tB - +tA) * 86400000) + ((($PIECE(tB, ",", 2)) - ($PIECE(tA, ",", 2))) * 1000)\1
}

/// "40 s", "3 min", "2 h".
ClassMethod Human(pMs As %Integer) As %String
{
	Quit $SELECT(pMs < 90000: (pMs + 500 \ 1000)_" s", pMs < 5400000: (pMs + 30000 \ 60000)_" min", 1: (pMs + 1800000 \ 3600000)_" h")
}

/// The steps. pHops: {From, To, T0, T1, Error, SessionId} in time order; pItems: see Items;
/// pTools: {Tool, Status, DurationMs, ResultLength, ErrorText, CreatedAt}; pUsage and pLearned are
/// objects or "". pSpanOutcome is the "triage decision" span's final outcome. Each step has kind,
/// title, text, at/endAt (UTC), durationMs, gapMs, status, session, and node or edge
/// ({from,to}) for the map; waitLabel when the step or the pause before it was long.
ClassMethod Build(pLog As AgenticProd.Data.DecisionLog, pNs As %String, pItems As %DynamicObject, pHops As %DynamicArray, pTools As %DynamicArray, pUsage As %DynamicObject = "", pLearned As %DynamicObject = "", pSpanOutcome As %String = "", ByRef pSecrets) As %DynamicObject
{
	Set tS0 = pLog.SessionId, tReviewed = pLog.ReviewedAt
	Set tOutcome = ##class(AgenticProd.UI.REST).TriageOutcome(pLog, pSpanOutcome)
	Set tSteps = []
	Set tAgentName = "", tRouterName = "", tFailedAt = "", tSentinel = "", tCheckName = "", tTaskTo = "", tInFrom = ""
	For tName = "inbound", "triage", "agent", "task", "later" Set tBucket(tName) = []

	// Sort hops into the phases of the path
	Set tIter = pHops.%GetIterator()
	While tIter.%GetNext(, .tHop) {
		// old item names kept in stored history map to the renamed items
		Do tHop.%Set("From", ##class(AgenticProd.UI.Flow).Alias(tHop.From)), tHop.%Set("To", ##class(AgenticProd.UI.Flow).Alias(tHop.To))
		Set tSrc = pItems.%Get($ZCONVERT(tHop.From, "U")), tDst = pItems.%Get($ZCONVERT(tHop.To, "U"))
		Set tSrcLane = $SELECT($IsObject(tSrc): tSrc.lane, 1: ""), tDstLane = $SELECT($IsObject(tDst): tDst.lane, 1: "")
		// A Sentinel hands the failure to Triage in a session of its own; those hops belong to the path
		// An operation that kept retrying until its FailureTimeout ends in status Error without IsError set
		If (tHop.SessionId = tS0) && (tHop.Error || (tHop.St = "Error")) && (tFailedAt = "") Set tFailedAt = tHop.To
		If tSrcLane = "sentinel" Set tSentinel = tHop.From, tCheckName = tHop.To
		If (tHop.SessionId '= tS0) && 'tHop.triage || ((tReviewed '= "") && (tHop.T0 ] tReviewed)) {
			Set tKind = "later"
		} ElseIf $IsObject(tDst) && tDst.workflow {
			Set tKind = "task", tTaskTo = tDst.name
		} ElseIf tDstLane = "ai" {
			Set tKind = "agent", tAgentName = tDst.name
		} ElseIf tSrcLane = "inbound" {
			Set tKind = "inbound", tRouterName = $SELECT($IsObject(tDst): tDst.name, 1: tHop.To)
			Set:(tInFrom = "") tInFrom = tHop.From
		} ElseIf tDstLane = "decision" {
			Set tKind = "triage"
		} Else {
			Set tKind = "later"
		}
		Set tList = tBucket($CASE(tKind, "agent": "agent", "task": "task", "inbound": "inbound", "triage": "triage", : "later"))
		Do tList.%Push(tHop)
	}
	Set tIter = pItems.%GetIterator()
	While (tAgentName = "") && tIter.%GetNext(.tKey, .tVal) {
		Set:tVal.lane="ai" tAgentName = tVal.name
	}

	Set tPrevEnd = ""
	// inbound hop(s)
	Do ..AddHops(tSteps, tBucket("inbound"), "inbound", "Inbound", .tPrevEnd, tReviewed)

	// router check: the message stopped there with its error text
	Set tAt = $SELECT(tPrevEnd'="": tPrevEnd, 1: pLog.CreatedAt)
	Set tWatch = (tSentinel '= "")
	Set tRouterText = $SELECT(tWatch && (tFailedAt '= ""): tRouterName_" could not deliver to "_tFailedAt_" ("_pLog.ErrorClass_"); "_tSentinel_" saw the failure: ", 1: "The router checked the message and stopped it ("_pLog.ErrorClass_"): ")
	Do ..Add(tSteps, "router", $SELECT(tWatch && (tFailedAt '= ""): "Delivery failed", 1: "Router check"), tRouterText_$SELECT(pLog.ErrorText '= "": ##class(AgenticProd.UI.REST).Mask(pLog.ErrorText, .pSecrets), 1: "no problem text recorded")_".", tAt, tAt, {"node":(tRouterName), "failedAt":($SELECT(tWatch: tFailedAt, 1: ""))}, tS0, "bad", .tPrevEnd)

	Do ..AddHops(tSteps, tBucket("triage"), "hop", "Failed message to Triage", .tPrevEnd, tReviewed)
	Do ..AddHops(tSteps, tBucket("agent"), "hop", "Triage asks the agent", .tPrevEnd, tReviewed)

	// agent and its tool calls, in the order they ran
	If '$IsObject(pUsage) || (pUsage.Decision = "") {
		Do ..Add(tSteps, "agent", "Agent", "The agent was not used for this message"_$SELECT(pLog.Reason '= "": ": "_##class(AgenticProd.UI.REST).Mask($EXTRACT(pLog.Reason, 1, 160), .pSecrets), 1: "")_".", tPrevEnd, tPrevEnd, {"node":(tAgentName)}, tS0, "warn", .tPrevEnd)
	} Else {
		Set tCalls = pTools.%Size(), tAgentFrom = tPrevEnd
		Set tTokens = +pUsage.PromptTokens + pUsage.CompletionTokens
		Set tText = $SELECT(pUsage.Replay: "Replayed from a recorded run: no LLM call, no tools run."_$SELECT(pUsage.PromptMismatch: " Recorded with a different prompt.", 1: ""), 1: "Called "_pUsage.Model_".")
		Set tText = tText_" It proposed "_pUsage.Decision_$SELECT(pUsage.Confidence '= "": " with confidence "_$FNUMBER(pUsage.Confidence, "", 2), 1: "")_"."
		Set tText = tText_" "_tCalls_" tool call"_$SELECT(tCalls=1: "", 1: "s")_", "_tTokens_" tokens, $"_$FNUMBER(+pUsage.CostUsd, "", 6)_" (tokens and cost are per run, not per tool call)."
		Do ..Add(tSteps, "agent", "Agent", tText, tPrevEnd, tPrevEnd, {"node":(tAgentName), "sub":"model", "tokens":(tTokens), "costUsd":(+pUsage.CostUsd)}, tS0, "ok", .tPrevEnd)
		Set tIter = pTools.%GetIterator()
		While tIter.%GetNext(, .tCall) {
			// a replay lists the recorded run's calls; their stamps are from that run, so they follow each other from the agent hop
			Set tBeg = tPrevEnd, tEnd = $SELECT(tCall.DurationMs '= "": ..Shift(tBeg, +tCall.DurationMs), 1: tBeg)
			If 'pUsage.Replay && (tCall.CreatedAt '= "") && (tCall.CreatedAt ] tAgentFrom) {
				Set tEnd = tCall.CreatedAt, tBeg = $SELECT(tCall.DurationMs '= "": ..Shift(tEnd, -tCall.DurationMs), 1: tEnd)
			}
			Set tResult = $CASE(tCall.Status, "OK": "returned "_+tCall.ResultLength_" characters", "DENIED": "refused by the read-only policy", : "failed"_$SELECT(tCall.ErrorText '= "": ": "_$EXTRACT(##class(AgenticProd.UI.REST).Mask(tCall.ErrorText, .pSecrets), 1, 120), 1: ""))
			Do ..Add(tSteps, "tool", "Tool: "_tCall.Tool, tCall.Tool_" "_tResult_$SELECT(tCall.DurationMs '= "": " in "_tCall.DurationMs_" ms", 1: "")_$SELECT(pUsage.Replay: " (recorded run)", 1: "")_".", tBeg, tEnd, {"node":(tAgentName), "sub":(..SubNode(tCall)), "tool":(tCall.Tool), "denied":(tCall.Status = "DENIED")}, tS0, $SELECT(tCall.Status = "OK": "ok", 1: "bad"), .tPrevEnd)
		}
	}

	// the three gates after the agent
	Set tFlags = ##class(AgenticProd.UI.Flow).InjectionFlags(pLog.DecisionJSON)
	Do ..Add(tSteps, "injection", "Injection check", $SELECT(tFlags.%Size(): "InjectionGuard flagged instruction-like text in "_##class(AgenticProd.UI.REST).Join(tFlags)_". The agent saw it only as marked data; nothing it proposes here can be applied automatically.", 1: "InjectionGuard found no instruction-like text in the free-text fields."), tPrevEnd, tPrevEnd, {"node":"@injection"}, tS0, $SELECT(tFlags.%Size(): "bad", 1: "ok"), .tPrevEnd)
	Set tGround = ##class(AgenticProd.UI.REST).GroundingStep(pLog, .pSecrets)
	If $IsObject(tGround) {
		Set tFailed = ""
		Set tIter = tGround.checks.%GetIterator()
		While tIter.%GetNext(, .tCheck) {
			Set:'tCheck.pass tFailed = tFailed_$SELECT(tFailed'="": "; ", 1: "")_tCheck.text
		}
		Do ..Add(tSteps, "grounding", "Grounding check", tGround.text_$SELECT(tFailed'="": " Failed: "_tFailed_".", 1: ""), tPrevEnd, tPrevEnd, {"node":"@grounding", "checks":(tGround.checks)}, tS0, $SELECT(tGround.status = "passed": "ok", tGround.status = "warned": "warn", 1: "bad"), .tPrevEnd)
	}
	Do ..Add(tSteps, "triage", "Triage rule", ##class(AgenticProd.UI.REST).TriageText(pLog, tOutcome, .pSecrets), tPrevEnd, tPrevEnd, {"node":"@triage", "outcome":(tOutcome)}, tS0, $SELECT(##class(AgenticProd.UI.Flow).OutcomeLane(tOutcome) = "rejected": "bad", ##class(AgenticProd.UI.Flow).OutcomeLane(tOutcome) = "person": "warn", 1: "ok"), .tPrevEnd)

	// workflow task: created by Triage, answered by a person (waiting when not yet)
	Set tReview = ##class(AgenticProd.UI.REST).ReviewStep(pLog, tOutcome, .pSecrets)
	Set tTasks = tBucket("task"), tTaskHop = tTasks.%Get(0)
	If tReview.status '= "none" {
		Set tTo = $SELECT($IsObject(tTaskHop): tTaskHop.To, 1: "")
		Set tAt = $SELECT($IsObject(tTaskHop): tTaskHop.T0, 1: tPrevEnd)
		If $IsObject(tTaskHop) {
			Do ..Add(tSteps, "hop", "Triage sends an approval task", "Triage created the approval task for "_tTo_".", tTaskHop.T0, $SELECT(tTaskHop.T1 '= "": tTaskHop.T1, 1: tTaskHop.T0), {"edge":{"from":(tTaskHop.From), "to":(tTaskHop.To)}}, tTaskHop.SessionId, $SELECT(tTaskHop.Error: "bad", 1: "ok"), .tPrevEnd)
			Set tAt = tPrevEnd
		}
		Set tEnd = $SELECT(tReviewed '= "": tReviewed, 1: $ZDATETIME($ZTIMESTAMP, 3, 1, 3))
		Set tNode = $SELECT(tTo '= "": {"node":(tTo)}, 1: {})
		Do ..Add(tSteps, "workflow", "Workflow task", tReview.text, tAt, tEnd, tNode, tS0, $CASE(tReview.status, "waiting": "wait", "rejected": "bad", : "ok"), .tPrevEnd)
		Set tLast = tSteps.%Get(tSteps.%Size() - 1)
		Do:tReviewed="" tLast.%Set("open", 1, "boolean")
		Set tWho = $SELECT(pLog.Reviewer '= "": pLog.Reviewer, 1: "the reviewer")
		Set tWaitMs = ..Diff(tAt, tEnd)
		Do:tWaitMs>..#LONGWAITMS tLast.%Set("waitLabel", $SELECT(tReviewed = "": "waiting "_..Human(tWaitMs)_" so far for human approval", 1: "waited "_..Human(tWaitMs)_" for "_tWho))
	}

	// learning: the approved mapping written to the lookup table
	If $IsObject(pLearned) {
		Do ..Add(tSteps, "learning", "Learned mapping", "LearnedMapping #"_pLearned.ID_" written: "_##class(AgenticProd.UI.REST).Mask(pLearned.LocalCode, .pSecrets)_" to LOINC "_pLearned.Loinc_$SELECT(pLearned.Display '= "": " ("_pLearned.Display_")", 1: "")_", approved by "_pLearned.Reviewer_".", $SELECT(pLearned.ApprovedAt '= "": pLearned.ApprovedAt, 1: tPrevEnd), $SELECT(pLearned.ApprovedAt '= "": pLearned.ApprovedAt, 1: tPrevEnd), {"node":"@triage", "sub":"memory", "learned":(pLearned.LocalCode)}, tS0, "ok", .tPrevEnd)
	}

	// resend and outbound hops, also from the sessions a resend started
	Do ..AddHops(tSteps, tBucket("later"), $SELECT(tReviewed '= "": "resend", 1: "out"), "", .tPrevEnd, tReviewed)

	// timing: real length of each step, the pause before it, long ones labelled
	Set tPrev = "", tN = 0, tIter = tSteps.%GetIterator()
	While tIter.%GetNext(, .tStep) {
		Do tStep.%Set("n", $INCREMENT(tN))
		Set tDur = ..Diff(tStep.at, tStep.endAt)
		Do tStep.%Set("durationMs", $SELECT(tDur > 0: tDur, 1: 0))
		Set tGap = $SELECT(tPrev '= "": ..Diff(tPrev, tStep.at), 1: 0)
		Do tStep.%Set("gapMs", $SELECT(tGap > 0: tGap, 1: 0))
		Do:(tGap > ..#LONGWAITMS)&&(tStep.waitLabel = "") tStep.%Set("waitLabel", "waited "_..Human(tGap))
		Set tPrev = $SELECT(tStep.endAt ] tStep.at: tStep.endAt, 1: tStep.at)
	}
	// The real item names along the path, only where a Sentinel carried the failure
	Set tPath = []
	If tWatch {
		For tPart = tInFrom, tRouterName, $SELECT(tFailedAt '= "": tFailedAt_" (fails)", 1: ""), tSentinel, tCheckName, tAgentName, tTaskTo {
			Do:tPart'="" tPath.%Push(tPart)
		}
	}
	Set tAgentCls = pItems.%Get($ZCONVERT(tAgentName, "U"))
	Quit {"id":(+pLog.%Id()), "headerId":(pLog.HeaderId), "sessionId":(tS0), "namespace":(pNs), "decision":(pLog.Decision), "errorClass":(pLog.ErrorClass), "createdAt":(pLog.CreatedAt), "outcome":(##class(AgenticProd.UI.Flow).OutcomeLane(tOutcome)),
		"traceUrl":(##class(AgenticProd.UI.REST).TraceUrl(pNs)), "agent":(..AgentInfo(tAgentName, pUsage, pTools, pLearned, $SELECT($IsObject(tAgentCls): tAgentCls.agentClass, 1: ""))), "steps":(tSteps),
		"path":(tPath), "sentinel":(tSentinel), "checkName":(tCheckName), "workflowName":(tTaskTo)}
}

/// The agent sub-node a tool call lights: knowledge, skills or tools. A refused call also shows on policies.
ClassMethod SubNode(pCall As %DynamicObject) As %String [ Internal ]
{
	Quit $CASE(pCall.Tool, "search_loinc": "knowledge", "load_skill": "skills", : "tools")
}

/// What the agent used for this message, one entry per sub-node of the canvas. Names come from the
/// agent class parameters, counts from the recorded tool calls.
ClassMethod AgentInfo(pName As %String, pUsage As %DynamicObject, pTools As %DynamicArray, pLearned As %DynamicObject, pAgentClass As %String = "") As %DynamicObject [ Internal ]
{
	Set tCls = $SELECT((pAgentClass '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(pAgentClass): pAgentClass, 1: "AgenticProd.Agent.TriageAgent"), tUsed = $IsObject(pUsage) && (pUsage.Decision '= "")
	Set tNames = [], tSeen = "", tAllowed = 0, tDenied = 0, tCand = 0, tSkillCalls = 0
	Set tIter = pTools.%GetIterator()
	While tIter.%GetNext(, .tCall) {
		If tCall.Status = "DENIED" { Set tDenied = tDenied + 1 } Else { Set tAllowed = tAllowed + 1 }
		Set tCand = tCand + (tCall.Tool = "search_loinc"), tSkillCalls = tSkillCalls + (tCall.Tool = "load_skill")
		Continue:((","_tSeen_",")[(","_tCall.Tool_","))
		Set tSeen = tSeen_$SELECT(tSeen'="": ",", 1: "")_tCall.Tool
		Do tNames.%Push(tCall.Tool)
	}
	Set tSkills = [], tSkillsUsed = []
	For i = 1:1:$LENGTH($PARAMETER(tCls, "SKILLS"), ",") {
		Set tOne = $PIECE($PIECE($PARAMETER(tCls, "SKILLS"), ",", i), ".", *)
		Do:tOne'="" tSkills.%Push(tOne)
		// build 154 does not audit load_skill: a skill counts as used when one of its tools was called
		Set tSkillCls = $PIECE($PARAMETER(tCls, "SKILLS"), ",", i)
		If (tOne'="") && ..SkillUsed(tSkillCls, tSeen) Do tSkillsUsed.%Push(tOne)
	}
	Quit {"name":(pName), "class":"%AI.Agent", "agentClass":(tCls), "used":(''tUsed),
		"model":($SELECT(tUsed: pUsage.Model, 1: "")), "provider":($PARAMETER(tCls, "PROVIDER")), "replay":($SELECT(tUsed: ''pUsage.Replay, 1: 0)),
		"sessionId":($SELECT(tUsed: pUsage.AgentSessionId, 1: "")),
		"decision":($SELECT(tUsed: pUsage.Decision, 1: "")), "confidence":($SELECT(tUsed: pUsage.Confidence, 1: "")),
		"tokens":($SELECT(tUsed: +pUsage.PromptTokens + pUsage.CompletionTokens, 1: 0)), "costUsd":($SELECT(tUsed: +pUsage.CostUsd, 1: 0)),
		"tools":(tNames), "skills":(tSkills), "skillsUsed":(tSkillsUsed), "skillCalls":(tSkillCalls), "searches":(tCand),
		"allowed":(tAllowed), "denied":(tDenied), "learned":($SELECT($IsObject(pLearned): pLearned.LocalCode, 1: ""))}
}

/// 1 when a tool method of skill class pSkillCls, in snake_case, is in the comma list pCalled.
ClassMethod SkillUsed(pSkillCls As %String, pCalled As %String) As %Boolean [ Internal ]
{
	Set tList = $PARAMETER(pSkillCls, "TOOLS")
	For i = 1:1:$LENGTH(tList, ",") {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledMethod WHERE parent = ? AND ClassMethod = 0 AND Internal = 0", $PIECE(tList, ",", i))
		While tRS.%Next() {
			Set tSnake = "", tName = tRS.Name
			For j = 1:1:$LENGTH(tName) {
				Set tCh = $EXTRACT(tName, j)
				Set tSnake = tSnake_$SELECT((j>1)&&(tCh?1U): "_", 1: "")_$ZCONVERT(tCh, "L")
			}
			Return:(","_pCalled_",")[(","_tSnake_",") 1
		}
	}
	Quit 0
}

/// pStep appended; pExtra adds node/edge/outcome. pPrevEnd is moved to the step's end.
ClassMethod Add(pSteps As %DynamicArray, pKind As %String, pTitle As %String, pText As %String, pAt As %String, pEnd As %String, pExtra As %DynamicObject, pSession As %Integer, pStatus As %String, ByRef pPrevEnd As %String) [ Internal ]
{
	Set pAt = $SELECT(pAt '= "": pAt, 1: pPrevEnd), pEnd = $SELECT(pEnd '= "": pEnd, 1: pAt)
	Set tStep = {"kind":(pKind), "title":(pTitle), "text":(pText), "at":(pAt), "endAt":(pEnd), "session":(pSession), "status":(pStatus), "waitLabel":""}
	Set tIter = pExtra.%GetIterator()
	While tIter.%GetNext(.tKey, .tVal) {
		Do tStep.%Set(tKey, tVal)
	}
	Do pSteps.%Push(tStep)
	Set pPrevEnd = pEnd
}

/// One step per hop: "A to B", with its time, or still open.
ClassMethod AddHops(pSteps As %DynamicArray, pHops As %DynamicArray, pKind As %String, pTitle As %String, ByRef pPrevEnd As %String, pReviewed As %String) [ Internal ]
{
	Set tIter = pHops.%GetIterator()
	While tIter.%GetNext(, .tHop) {
		Set tKind = pKind, tTitle = $SELECT(pTitle '= "": pTitle_": ", 1: "")_tHop.From_" to "_tHop.To
		Set:pKind="resend" tTitle = "Resend: "_tHop.From_" to "_tHop.To
		Set tMs = ..Diff(tHop.T0, tHop.T1)
		Set tText = $SELECT(tHop.T1 = "": "Still open.", 1: "Handled in "_$SELECT(tMs > 0: tMs, 1: 0)_" ms.")
		// this hop covers the whole Triage run, agent included
		If (pKind = "hop") && (pTitle [ "to Triage") Set tText = $SELECT(tHop.T1 = "": "Still open.", 1: "Triage total (includes agent): "_$FNUMBER($SELECT(tMs > 0: tMs, 1: 0) / 1000, "", 1)_" s.")_$SELECT(tHop.Error: " The hop ended in an error.", 1: "")
		Do ..Add(pSteps, tKind, tTitle, tText, tHop.T0, $SELECT(tHop.T1 '= "": tHop.T1, 1: tHop.T0), {"edge":{"from":(tHop.From), "to":(tHop.To)}}, tHop.SessionId, $SELECT(tHop.Error: "bad", 1: "ok"), .pPrevEnd)
	}
}

/// UTC timestamp pTs moved by pMs milliseconds.
ClassMethod Shift(pTs As %String, pMs As %Integer) As %String [ Internal ]
{
	Set tH = $ZDATETIMEH(pTs, 3), tSec = $PIECE(tH, ",", 2) + (pMs / 1000), tDay = +tH
	While tSec < 0 {
		Set tSec = tSec + 86400, tDay = tDay - 1
	}
	While tSec >= 86400 {
		Set tSec = tSec - 86400, tDay = tDay + 1
	}
	Quit $ZDATETIME(tDay_","_tSec, 3, 1, 3)
}

}
