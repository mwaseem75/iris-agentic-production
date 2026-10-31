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
	Set tUsage = ##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 Model, Replay, Decision, Confidence, AgentSessionId, PromptTokens, CompletionTokens, CostUsd, DecisionJSON FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND Namespace = ? ORDER BY ID DESC", tLog.HeaderId, pNs).%Get(0)
	Set tTools = $SELECT($IsObject(tUsage)&&(tUsage.AgentSessionId '= ""): ##class(AgenticProd.UI.REST).Rows("SELECT Tool, Status, DurationMs, ResultLength, ErrorText, CreatedAt FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? ORDER BY ID", tUsage.AgentSessionId, pNs), 1: [])
	Set tLearned = ##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 ID, LocalCode, Loinc, Display, Reviewer, ApprovedAt FROM AgenticProd_Data.LearnedMapping WHERE DecisionLogId = ? AND Origin = 'Approved' ORDER BY ID DESC", pId).%Get(0)
	Set tMessage = ##class(AgenticProd.UI.REST).MaskedMessage(tLog.HeaderId, .tSecrets, pNs)
	Quit ..Build(tLog, pNs, ..Items(), ..Hops(tLog.SessionId), tTools, tUsage, tLearned, tSpanOutcome, .tSecrets)
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
		Do tItems.%Set($ZCONVERT(tItem.Name, "U"), {"name":(tItem.Name), "lane":(##class(AgenticProd.UI.Flow).Lane(tClass)), "workflow":(''tWorkflow)})
	}
	Quit tItems
}

/// Request hops of the message's session and of the sessions its resends started, in header order.
ClassMethod Hops(pSessionId As %Integer) As %DynamicArray
{
	Quit:pSessionId="" []
	Set tSessions = pSessionId
	// a resent copy may start its own session; Resent on the original points to it
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT SessionId FROM Ens.MessageHeader WHERE ID IN (SELECT Resent FROM Ens.MessageHeader WHERE SessionId = ? AND Resent > 0) OR SuperSession = ?", pSessionId, pSessionId)
	While tRS.%Next() {
		Set:(tRS.SessionId'="")&&((","_tSessions_",")'[(","_tRS.SessionId_",")) tSessions = tSessions_","_tRS.SessionId
	}
	Quit ##class(AgenticProd.UI.REST).Rows("SELECT ID, SessionId, SourceConfigName AS ""From"", TargetConfigName AS ""To"", TimeCreated AS T0, TimeProcessed AS T1, IsError AS Error FROM Ens.MessageHeader"
		_" WHERE Type = 1 AND SessionId IN ("_tSessions_") AND NOT SourceConfigName %STARTSWITH 'Ens.' AND NOT TargetConfigName %STARTSWITH 'Ens.' ORDER BY ID")
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
	Set tAgentName = "", tRouterName = ""
	For tName = "inbound", "triage", "agent", "task", "later" Set tBucket(tName) = []

	// Sort hops into the phases of the path
	Set tIter = pHops.%GetIterator()
	While tIter.%GetNext(, .tHop) {
		Set tSrc = pItems.%Get($ZCONVERT(tHop.From, "U")), tDst = pItems.%Get($ZCONVERT(tHop.To, "U"))
		Set tSrcLane = $SELECT($IsObject(tSrc): tSrc.lane, 1: ""), tDstLane = $SELECT($IsObject(tDst): tDst.lane, 1: "")
		If (tHop.SessionId '= tS0) || ((tReviewed '= "") && (tHop.T0 ] tReviewed)) {
			Set tKind = "later"
		} ElseIf $IsObject(tDst) && tDst.workflow {
			Set tKind = "task"
		} ElseIf tDstLane = "ai" {
			Set tKind = "agent", tAgentName = tDst.name
		} ElseIf tSrcLane = "inbound" {
			Set tKind = "inbound", tRouterName = $SELECT($IsObject(tDst): tDst.name, 1: tHop.To)
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
	Do ..Add(tSteps, "router", "Router check", "The router checked the message and stopped it ("_pLog.ErrorClass_"): "_$SELECT(pLog.ErrorText '= "": ##class(AgenticProd.UI.REST).Mask(pLog.ErrorText, .pSecrets), 1: "no problem text recorded")_".", tAt, tAt, {"node":(tRouterName)}, tS0, "bad", .tPrevEnd)

	Do ..AddHops(tSteps, tBucket("triage"), "hop", "Failed message to Triage", .tPrevEnd, tReviewed)
	Do ..AddHops(tSteps, tBucket("agent"), "hop", "Triage asks the agent", .tPrevEnd, tReviewed)

	// agent and its tool calls, in the order they ran
	If '$IsObject(pUsage) || (pUsage.Decision = "") {
		Do ..Add(tSteps, "agent", "Agent", "The agent was not used for this message"_$SELECT(pLog.Reason '= "": ": "_##class(AgenticProd.UI.REST).Mask($EXTRACT(pLog.Reason, 1, 160), .pSecrets), 1: "")_".", tPrevEnd, tPrevEnd, {"node":(tAgentName)}, tS0, "warn", .tPrevEnd)
	} Else {
		Set tCalls = pTools.%Size(), tAgentFrom = tPrevEnd
		Set tTokens = +pUsage.PromptTokens + pUsage.CompletionTokens
		Set tText = $SELECT(pUsage.Replay: "Replayed from a recorded run: no LLM call, no tools run.", 1: "Called "_pUsage.Model_".")
		Set tText = tText_" It proposed "_pUsage.Decision_$SELECT(pUsage.Confidence '= "": " with confidence "_$FNUMBER(pUsage.Confidence, "", 2), 1: "")_"."
		Set tText = tText_" "_tCalls_" tool call"_$SELECT(tCalls=1: "", 1: "s")_", "_tTokens_" tokens, $"_$FNUMBER(+pUsage.CostUsd, "", 6)_" (tokens and cost are per run, not per tool call)."
		Do ..Add(tSteps, "agent", "Agent", tText, tPrevEnd, tPrevEnd, {"node":(tAgentName)}, tS0, "ok", .tPrevEnd)
		Set tIter = pTools.%GetIterator()
		While tIter.%GetNext(, .tCall) {
			// a replay lists the recorded run's calls; their stamps are from that run, so they follow each other from the agent hop
			Set tBeg = tPrevEnd, tEnd = $SELECT(tCall.DurationMs '= "": ..Shift(tBeg, +tCall.DurationMs), 1: tBeg)
			If 'pUsage.Replay && (tCall.CreatedAt '= "") && (tCall.CreatedAt ] tAgentFrom) {
				Set tEnd = tCall.CreatedAt, tBeg = $SELECT(tCall.DurationMs '= "": ..Shift(tEnd, -tCall.DurationMs), 1: tEnd)
			}
			Set tResult = $CASE(tCall.Status, "OK": "returned "_+tCall.ResultLength_" characters", "DENIED": "refused by the read-only policy", : "failed"_$SELECT(tCall.ErrorText '= "": ": "_$EXTRACT(##class(AgenticProd.UI.REST).Mask(tCall.ErrorText, .pSecrets), 1, 120), 1: ""))
			Do ..Add(tSteps, "tool", "Tool: "_tCall.Tool, tCall.Tool_" "_tResult_$SELECT(tCall.DurationMs '= "": " in "_tCall.DurationMs_" ms", 1: "")_$SELECT(pUsage.Replay: " (recorded run)", 1: "")_".", tBeg, tEnd, {"node":(tAgentName)}, tS0, $SELECT(tCall.Status = "OK": "ok", 1: "bad"), .tPrevEnd)
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
		Do ..Add(tSteps, "grounding", "Grounding check", tGround.text_$SELECT(tFailed'="": " Failed: "_tFailed_".", 1: ""), tPrevEnd, tPrevEnd, {"node":"@grounding"}, tS0, $SELECT(tGround.status = "passed": "ok", tGround.status = "warned": "warn", 1: "bad"), .tPrevEnd)
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
		Do:tWaitMs>..#LONGWAITMS tLast.%Set("waitLabel", $SELECT(tReviewed = "": "waiting "_..Human(tWaitMs)_" so far for the reviewer", 1: "waited "_..Human(tWaitMs)_" for "_tWho))
	}

	// learning: the approved mapping written to the lookup table
	If $IsObject(pLearned) {
		Do ..Add(tSteps, "learning", "Learned mapping", "LearnedMapping #"_pLearned.ID_" written: "_##class(AgenticProd.UI.REST).Mask(pLearned.LocalCode, .pSecrets)_" to LOINC "_pLearned.Loinc_$SELECT(pLearned.Display '= "": " ("_pLearned.Display_")", 1: "")_", approved by "_pLearned.Reviewer_".", $SELECT(pLearned.ApprovedAt '= "": pLearned.ApprovedAt, 1: tPrevEnd), $SELECT(pLearned.ApprovedAt '= "": pLearned.ApprovedAt, 1: tPrevEnd), {"node":"@triage"}, tS0, "ok", .tPrevEnd)
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
	Quit {"id":(+pLog.%Id()), "headerId":(pLog.HeaderId), "sessionId":(tS0), "namespace":(pNs), "decision":(pLog.Decision), "outcome":(##class(AgenticProd.UI.Flow).OutcomeLane(tOutcome)),
		"traceUrl":(##class(AgenticProd.UI.REST).TraceUrl(pNs)), "steps":(tSteps)}
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
		Set tText = $SELECT(tHop.T1 = "": "Still open.", 1: "Handled in "_$SELECT(tMs > 0: tMs, 1: 0)_" ms.")_$SELECT(tHop.Error: " The hop ended in an error.", 1: "")
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
