Include Ensemble

/// Data behind the dashboard's Flow tab: the production map with counters, the hops, decisions and
/// tool calls since a cursor, and the burst planner. Reads Ens.MessageHeader and the Data tables
/// only; Burst writes sample files for LabFileIn, nothing else. The REST class and the tests call
/// these methods directly.
Class AgenticProd.UI.Flow Extends %RegisteredObject
{

/// Namespaces the tab can show.
Parameter NAMESPACES = "IRISAPP,LEGACY";

/// Rows per kind in one answer; "capped" tells the page there was more.
Parameter CAP = 200;

/// Minutes the map counters and the first window cover.
Parameter MAPMINUTES = 60;

/// Seconds an unfinished hop keeps the cursor back, so its end time is picked up. Older ones are stuck.
Parameter OPENHOPSECONDS = 120;

Parameter BURSTDEFAULT = 8;

Parameter BURSTMAX = 30;

/// Live bursts spend credit, so the cap is small.
Parameter BURSTLIVEMAX = 10;

/// Control IDs are EV<BURSTRUN + n>-<case>, n counting bursts: Agent.Replay finds the recorded run
/// by the case ID, and a run number no EvalRun has keeps the rows out of eval runs, Cost and the
/// live Messages list.
Parameter BURSTRUN = 900000;

/// Live bursts count from here. Replay bursts (BURSTRUN up to here) are the only messages the agent
/// replays while its Mode stays live; see IsReplayBurst.
Parameter BURSTLIVERUN = 950000;

/// Eval run ids from BURSTRUN up to here are bursts; test stubs use 9999xx.
Parameter BURSTEND = 999000;

Parameter FALLBACKCOSTUSD = 0.0015;

/// pNs when the tab may show it, the current namespace for "", else "".
ClassMethod CheckNs(pNs As %String) As %String
{
	Quit:pNs="" $NAMESPACE
	Quit $SELECT((","_..#NAMESPACES_",")[(","_pNs_","): pNs, 1: "")
}

/// Item names before the US rename; stored headers and spans still carry them.
ClassMethod Alias(pName As %String) As %String
{
	Quit $CASE(pName, "NphiesOut": "EhrOut", "NphiesFHIROut": "FhirOut", : pName)
}

/// Map lane of a production item: inbound, router, ai, decision or outcome.
ClassMethod Lane(pClass As %String) As %String
{
	Quit:pClass="AgenticProd.Process.Triage" "decision"
	Quit:pClass="AgenticProd.Operation.Agent" "ai"
	Quit:pClass="AgenticProd.Plugin.Sentinel" "sentinel"
	Quit:'##class(%Dictionary.CompiledClass).%ExistsId(pClass) "router"
	Quit:$CLASSMETHOD(pClass, "%IsA", "Ens.BusinessService") "inbound"
	Quit:$CLASSMETHOD(pClass, "%IsA", "Ens.BusinessOperation") "outcome"
	Quit "router"
}

/// Lane on the Flow tab's map, which has no sentinel column: the Sentinel stays with the inbound services.
ClassMethod MapLane(pClass As %String) As %String
{
	Set tLane = ..Lane(pClass)
	Quit $SELECT(tLane = "sentinel": "inbound", 1: tLane)
}

/// UTC timestamp pMinutes ago, to the millisecond.
ClassMethod Ago(pMinutes As %Integer) As %String
{
	Set tNow = $ZTIMESTAMP, tDay = +tNow, tSec = $PIECE(tNow, ",", 2) - (pMinutes * 60)
	While tSec < 0 {
		Set tSec = tSec + 86400, tDay = tDay - 1
	}
	Quit $ZDATETIME(tDay_","_tSec, 3, 1, 3)
}

/// Dashboard outcome lane of a Triage outcome (REST.TriageOutcome): applied, person, rejected,
/// resent or observed. A send that failed still needs a person.
ClassMethod OutcomeLane(pTriageOutcome As %String) As %String
{
	Quit:pTriageOutcome="APPLIED" "applied"
	Quit:pTriageOutcome="REJECTED" "rejected"
	Quit:pTriageOutcome="RESENT" "resent"
	Quit:$EXTRACT(pTriageOutcome, 1, 9)="OBSERVED:" "observed"
	Quit "person"
}

/// Grounding gate as the page shows it: {status: none|passed|ungrounded|ambiguous, check}.
ClassMethod GroundingGate(pGroundingJSON As %String, pGrounded As %Boolean, pFailed As %String) As %DynamicObject
{
	Quit:pGroundingJSON="" {"status":"none", "check":""}
	Quit:pGrounded {"status":"passed", "check":""}
	Set tCheck = $PIECE(pFailed, ",")
	Quit {"status":($SELECT((","_pFailed_",")[",ambiguity,": "ambiguous", 1: "ungrounded")), "check":(tCheck)}
}

/// Paths InjectionGuard flagged, from the agent's evidence lines.
ClassMethod InjectionFlags(pDecisionJSON As %String) As %DynamicArray
{
	Set tFlags = []
	Quit:pDecisionJSON="" tFlags
	Set tDecision = ##class(%DynamicObject).%FromJSON(pDecisionJSON)
	Quit:'$IsObject(tDecision.evidence) tFlags
	Set tEv = tDecision.evidence.%GetIterator()
	While tEv.%GetNext(, .tLine) {
		Do:$EXTRACT(tLine, 1, 26)="suspicious instruction in " tFlags.%Push($PIECE($EXTRACT(tLine, 27, *), ": "))
	}
	Quit tFlags
}

/// Map for pNs over pFrom..pTo (UTC timestamps; "" = the last MAPMINUTES to now): the production's
/// items in lanes with in/out/error counts and queue depth, and the hops between them with their
/// average time. Only items of the production are shown, not Ens.* system hosts. Unless
/// pIncludeEval, sessions that have an eval DecisionLog row (bursts excepted) are left out of the counts (a
/// message that passed the router has no such row, so clean eval traffic is still counted).
ClassMethod Map(pNs As %String, pFrom As %String = "", pTo As %String = "", pIncludeEval As %Boolean = 1) As %DynamicObject
{
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set:pFrom="" pFrom = ..Ago(..#MAPMINUTES)
	Set:pTo="" pTo = "9999-12-31 23:59:59"
	Set tName = ##class(Ens.Director).GetActiveProductionName()
	Set:tName="" tName = $GET(^Ens.Configuration("csp", "LastProduction"))
	Set tOut = {"ns":(pNs), "production":(tName), "from":(pFrom), "lanes":["inbound","router","ai","checks","decision","outcome"], "items":[], "edges":[]}
	Quit:tName="" tOut
	Set tProd = ##class(Ens.Config.Production).%OpenId(tName)
	Quit:'$IsObject(tProd) tOut

	Set tWhere = " WHERE Type = 1 AND TimeCreated >= ? AND TimeCreated <= ?"_$SELECT(pIncludeEval: "", 1: " AND SessionId NOT IN (SELECT SessionId FROM AgenticProd_Data.DecisionLog WHERE EvalRunId IS NOT NULL AND NOT (EvalRunId >= "_..#BURSTRUN_" AND EvalRunId < "_..#BURSTEND_") AND SessionId IS NOT NULL AND Namespace = '"_pNs_"')")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName AS N, COUNT(*) AS C, SUM(IsError) AS E FROM Ens.MessageHeader"_tWhere_" GROUP BY TargetConfigName", pFrom, pTo)
	While tRS.%Next() {
		Set tK = $ZCONVERT(..Alias(tRS.N), "U"), tIn(tK) = $GET(tIn(tK)) + tRS.C, tErr(tK) = $GET(tErr(tK)) + tRS.E
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT SourceConfigName AS N, COUNT(*) AS C FROM Ens.MessageHeader"_tWhere_" GROUP BY SourceConfigName", pFrom, pTo)
	While tRS.%Next() {
		Set tK = $ZCONVERT(..Alias(tRS.N), "U"), tOutN(tK) = $GET(tOutN(tK)) + tRS.C
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, ""Count"" AS Depth FROM Ens.Queue_Enumerate()")
	While tRS.%Next() {
		Set tQueue($ZCONVERT(tRS.Name, "U")) = tRS.Depth
	}

	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i), tN = tItem.Name, tU = $ZCONVERT(tN, "U"), tItems(tU) = tN
		Do tOut.items.%Push({"name":(tN), "className":(tItem.ClassName), "lane":(..MapLane(tItem.ClassName)), "enabled":(''tItem.Enabled),
			"note":($SELECT((tItem.ClassName = "AgenticProd.Operation.FhirOut") && '##class(AgenticProd.Paths).FhirAvailable(): ##class(AgenticProd.Paths).#FHIRNOTE, 1: "")),
			"in":(+$GET(tIn(tU))), "out":(+$GET(tOutN(tU))), "errors":(+$GET(tErr(tU))), "queue":(+$GET(tQueue(tU)))})
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT SourceConfigName AS S, TargetConfigName AS T, COUNT(*) AS C, AVG(DATEDIFF('ms', TimeCreated, TimeProcessed)) AS Ms"
		_" FROM Ens.MessageHeader"_tWhere_" GROUP BY SourceConfigName, TargetConfigName", pFrom, pTo)
	While tRS.%Next() {
		Set tFrom = $GET(tItems($ZCONVERT(..Alias(tRS.S), "U"))), tTo = $GET(tItems($ZCONVERT(..Alias(tRS.T), "U")))
		Do:(tFrom'="")&&(tTo'="") tOut.edges.%Push({"from":(tFrom), "to":(tTo), "count":(tRS.C), "avgMs":(+tRS.Ms\1)})
	}
	Quit tOut
}

/// Rows newer than the cursor, or in pFrom..pTo when the cursor is empty:
/// hops (request headers between production items, end time null while open), decisions with their
/// gates, tool calls and usage rows. Each kind stops at CAP rows. cursor is what to send back next time.
ClassMethod Slice(pNs As %String, pFrom As %String = "", pTo As %String = "", pCursor As %DynamicObject = "") As %DynamicObject
{
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set:pFrom="" pFrom = "0000-01-01 00:00:00"
	Set:pTo="" pTo = "9999-12-31 23:59:59"
	Set:'$IsObject(pCursor) pCursor = {}
	Set tCap = ..#CAP
	Set tOut = {"ns":(pNs), "now":(..Ago(0)), "hops":[], "decisions":[], "tools":[], "usage":[], "capped":false}
	Set tCursor = {"hop":(+pCursor.hop), "dec":(+pCursor.dec), "tool":(+pCursor.tool), "usage":(+pCursor.usage)}

	Set tStuckCut = ..Ago(..#OPENHOPSECONDS / 60), tLowOpen = ""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_(tCap + 1)_" ID, SessionId, SourceConfigName, TargetConfigName, TimeCreated, TimeProcessed, IsError FROM Ens.MessageHeader"
		_" WHERE Type = 1 AND ID > ? AND TimeCreated >= ? AND TimeCreated <= ? AND NOT SourceConfigName %STARTSWITH 'Ens.' AND NOT TargetConfigName %STARTSWITH 'Ens.' ORDER BY ID", tCursor.hop, pFrom, pTo)
	Set tN = 0
	While tRS.%Next() {
		If $INCREMENT(tN) > tCap Set tOut.capped = 1 Quit
		Set tDone = tRS.TimeProcessed '= ""
		Set tHop = {"id":(tRS.ID), "session":(tRS.SessionId), "from":(..Alias(tRS.SourceConfigName)), "to":(..Alias(tRS.TargetConfigName)),
			"t0":(tRS.TimeCreated), "t1":($SELECT(tDone: tRS.TimeProcessed, 1: "")), "error":(''tRS.IsError)}
		Set tOpen = 'tDone && (tRS.TimeCreated ] tStuckCut)
		Do tHop.%Set("open", tOpen, "boolean")
		Do tOut.hops.%Push(tHop)
		Set:tOpen&&(tLowOpen = "") tLowOpen = +tRS.ID
		Set tCursor.hop = +tRS.ID
	}
	Set:tLowOpen'="" tCursor.hop = tLowOpen - 1

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_(tCap + 1)_" ID FROM AgenticProd_Data.DecisionLog WHERE Namespace = ? AND ID > ? AND CreatedAt >= ? AND CreatedAt <= ? ORDER BY ID", pNs, tCursor.dec, pFrom, pTo)
	Set tN = 0
	While tRS.%Next() {
		If $INCREMENT(tN) > tCap Set tOut.capped = 1 Quit
		Do tOut.decisions.%Push(..Card(tRS.ID))
		Set tCursor.dec = +tRS.ID
	}

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_(tCap + 1)_" ID, HeaderId, AgentSessionId, Tool, Status, DurationMs, CreatedAt FROM AgenticProd_Data.ToolCall WHERE Namespace = ? AND ID > ? AND CreatedAt >= ? AND CreatedAt <= ? ORDER BY ID", pNs, tCursor.tool, pFrom, pTo)
	Set tN = 0
	While tRS.%Next() {
		If $INCREMENT(tN) > tCap Set tOut.capped = 1 Quit
		Do tOut.tools.%Push({"id":(tRS.ID), "headerId":(tRS.HeaderId), "tool":(tRS.Tool), "status":(tRS.Status), "ms":(+tRS.DurationMs), "at":(tRS.CreatedAt)})
		Set tCursor.tool = +tRS.ID
	}

	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_(tCap + 1)_" ID, HeaderId, Model, PromptTokens, CompletionTokens, CostUsd, Replay, CreatedAt FROM AgenticProd_Data.Usage WHERE Namespace = ? AND ID > ? AND CreatedAt >= ? AND CreatedAt <= ? ORDER BY ID", pNs, tCursor.usage, pFrom, pTo)
	Set tN = 0
	While tRS.%Next() {
		If $INCREMENT(tN) > tCap Set tOut.capped = 1 Quit
		Do tOut.usage.%Push({"id":(tRS.ID), "headerId":(tRS.HeaderId), "model":(tRS.Model), "tokens":(+tRS.PromptTokens + tRS.CompletionTokens), "costUsd":(+tRS.CostUsd), "replay":(''tRS.Replay), "at":(tRS.CreatedAt)})
		Set tCursor.usage = +tRS.ID
	}
	Set tOut.cursor = tCursor
	Quit tOut
}

/// Where a message stands now. DecisionLog.Outcome is what Triage did until a reviewer answers, then
/// the answer (APPROVED, REVIEW_*). An open approval task shows as "waiting".
ClassMethod Status(pOutcome As %String, pReviewedAt As %String) As %String
{
	Quit:(pReviewedAt="")&&((pOutcome="SENT_FOR_APPROVAL")||($EXTRACT(pOutcome, 1, 11)="DOWNGRADED:")||($EXTRACT(pOutcome, 1, 9)="PROPOSED:")) "waiting"
	Quit:$EXTRACT(pOutcome, 1, 9)="OBSERVED:" "OBSERVED"
	Quit:$EXTRACT(pOutcome, 1, 6)="ERROR:" "ERROR"
	Quit:pOutcome="" "waiting"
	Quit pOutcome
}

/// Newest pLimit messages of pNs, newest first, for the Flow tab's list. status is the current one
/// (see Status). Eval rows are left out unless pIncludeEval; burst rows follow the same rule.
ClassMethod Messages(pNs As %String, pIncludeEval As %Boolean = 0, pLimit As %Integer = 25) As %DynamicArray
{
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set pLimit = $SELECT(pLimit<1: 25, pLimit>60: 60, 1: pLimit\1)
	Set tRows = ##class(AgenticProd.UI.REST).Rows("SELECT TOP ? d.ID, d.HeaderId, d.CreatedAt, d.EvalRunId, d.ErrorClass, d.ErrorText, d.Decision, d.Outcome, d.ReviewedAt,"
		_" (SELECT MAX(t.ControlId) FROM AgenticProd_Msg.TriageRequest t WHERE t.HeaderId = d.HeaderId) AS ControlId"
		_" FROM AgenticProd_Data.DecisionLog d WHERE d.Namespace = ?"_$SELECT(pIncludeEval: "", 1: " AND (d.EvalRunId IS NULL OR (d.EvalRunId >= "_..#BURSTRUN_" AND d.EvalRunId < "_..#BURSTEND_"))")
		_" ORDER BY d.ID DESC", pLimit, pNs)
	Set tOut = []
	Set tIter = tRows.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Kill tSecrets
		Set tText = ""
		If tRow.ErrorText '= "" {
			Do ##class(AgenticProd.UI.REST).MaskedMessage(tRow.HeaderId, .tSecrets, pNs)
			Set tText = ##class(AgenticProd.UI.REST).Mask($EXTRACT(tRow.ErrorText, 1, 90), .tSecrets)
		}
		Do tOut.%Push({"id":(+tRow.ID), "headerId":(tRow.HeaderId), "at":(tRow.CreatedAt), "controlId":(tRow.ControlId), "errorClass":(tRow.ErrorClass), "error":(tText),
			"decision":(tRow.Decision), "status":(..Status(tRow.Outcome, tRow.ReviewedAt)),
			"eval":(tRow.EvalRunId '= ""), "burst":((tRow.EvalRunId '= "") && (tRow.EvalRunId >= ..#BURSTRUN) && (tRow.EvalRunId < ..#BURSTEND))})
	}
	Quit tOut
}

/// Cursor at the newest rows of pNs, for a live poll that starts from now.
ClassMethod Head(pNs As %String) As %DynamicObject
{
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set tHop = ..MaxId("Ens.MessageHeader", "")
	Set tDec = ..MaxId("AgenticProd_Data.DecisionLog", pNs)
	Set tTool = ..MaxId("AgenticProd_Data.ToolCall", pNs)
	Set tUsage = ..MaxId("AgenticProd_Data.Usage", pNs)
	Quit {"ns":(pNs), "now":(..Ago(0)), "hops":[], "decisions":[], "tools":[], "usage":[], "capped":false, "cursor":{"hop":(tHop), "dec":(tDec), "tool":(tTool), "usage":(tUsage)}}
}

ClassMethod MaxId(pTable As %String, pNs As %String) As %Integer [ Internal ]
{
	// an extra "" argument with no ? in the SQL makes the query return nothing
	Set tSQL = "SELECT MAX(ID) AS M FROM "_pTable_$SELECT(pNs'="": " WHERE Namespace = ?", 1: "")
	Set tRS = $SELECT(pNs'="": ##class(%SQL.Statement).%ExecDirect(, tSQL, pNs), 1: ##class(%SQL.Statement).%ExecDirect(, tSQL))
	Quit $SELECT(tRS.%Next(): +tRS.M, 1: 0)
}

/// One decision as the page needs it: the three gates (injection, grounding, Triage rule), the
/// outcome lane, tokens and cost. Only fields the page shows; the story view has the rest.
ClassMethod Card(pId As %String) As %DynamicObject
{
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pId)
	Set tSpan = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Attributes FROM AgenticProd_Data.Span WHERE HeaderId = ? AND Namespace = ? AND Name = 'triage decision' ORDER BY ID DESC", tLog.HeaderId, tLog.Namespace)
	Set tSpanOutcome = ""
	If tSpan.%Next() && (tSpan.Attributes '= "") Set tSpanOutcome = ##class(%DynamicObject).%FromJSON(tSpan.Attributes).%Get("agentic.final_outcome")
	Set tRule = ##class(AgenticProd.UI.REST).TriageOutcome(tLog, tSpanOutcome)
	Set tFlags = ..InjectionFlags(tLog.DecisionJSON)
	Set tUsage = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 PromptTokens + CompletionTokens AS Tokens, CostUsd, Replay FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND Namespace = ? ORDER BY ID DESC", tLog.HeaderId, tLog.Namespace)
	Set tHasUsage = tUsage.%Next()
	Quit {"id":(+pId), "headerId":(tLog.HeaderId), "session":(tLog.SessionId), "decision":(tLog.Decision), "errorClass":(tLog.ErrorClass), "confidence":(+tLog.Confidence),
		"at":(tLog.CreatedAt), "eval":(tLog.EvalRunId '= ""), "burst":((tLog.EvalRunId '= "") && (tLog.EvalRunId >= ..#BURSTRUN) && (tLog.EvalRunId < ..#BURSTEND)),
		"gates":{"injection":{"status":($SELECT(tFlags.%Size(): "flagged", 1: "clean")), "flagged":(tFlags)},
			"grounding":(..GroundingGate(tLog.GroundingJSON, tLog.Grounded, tLog.GroundingFailed)),
			"triage":{"outcome":(tRule)}},
		"outcome":(..OutcomeLane(tRule)),
		"tokens":($SELECT(tHasUsage: +tUsage.Tokens, 1: 0)), "costUsd":($SELECT(tHasUsage: +tUsage.CostUsd, 1: 0)), "replay":($SELECT(tHasUsage: ''tUsage.Replay, 1: 0))}
}

/// Plan, and unless pDryRun send, a burst of pBody.n eval cases as new messages. Nothing here
/// changes a setting: a replay burst works in any mode (the agent replays its control IDs), live needs live mode, a live burst
/// needs confirm and at most BURSTLIVEMAX cases. pAgent overrides the agent's settings for tests
/// ({mode, killSwitch, budget, used, model}). Returns {ok, status (HTTP), error, ...}.
ClassMethod Burst(pBody As %DynamicObject, pCanEdit As %Boolean, pDryRun As %Boolean = 0, pAgent As %DynamicObject = "") As %DynamicObject
{
	Quit:'pCanEdit ..Refuse(403, "Sending a burst needs the AgenticProd_Admin role")
	If '$IsObject(pAgent) {
		Set pAgent = {"mode":(##class(AgenticProd.UI.REST).AgentSetting("TriageAgent", "Mode")), "killSwitch":(+##class(AgenticProd.UI.REST).AgentSetting("TriageAgent", "KillSwitch")),
			"budget":(+##class(AgenticProd.UI.REST).AgentSetting("TriageAgent", "DailyTokenBudget")), "used":(##class(AgenticProd.Operation.Agent).TokensUsedToday()),
			"model":(##class(AgenticProd.UI.REST).AgentSetting("TriageAgent", "Model"))}
	}
	Set tLive = (pBody.%Get("mode") = "live")
	Set tN = $SELECT(pBody.%Get("n") = "": ..#BURSTDEFAULT, 1: pBody.%Get("n"))
	Quit:(tN'?1.N)||(tN<1)||(tN>..#BURSTMAX) ..Refuse(400, "n must be a whole number from 1 to "_..#BURSTMAX)
	Quit:..CheckNs(pBody.%Get("ns"))'="IRISAPP" ..Refuse(400, "Bursts go to IRISAPP's LabFileIn only")
	Quit:pAgent.killSwitch ..Refuse(409, "The AI kill switch is on; every failed message would go to a person")
	// a replay burst needs no mode: the agent replays its own control IDs while it stays live
	Quit:tLive&&(pAgent.mode'="live") ..Refuse(409, "The agent is in "_pAgent.mode_" mode; change it in Settings to send a live burst")
	If tLive {
		Quit:tN>..#BURSTLIVEMAX ..Refuse(400, "A live burst is limited to "_..#BURSTLIVEMAX_" cases")
		Quit:pAgent.budget&&(pAgent.used>=pAgent.budget) ..Refuse(409, "The daily token budget is used up ("_pAgent.used_" of "_pAgent.budget_")")
	}
	Set tPool = ..CasePool(tLive, pAgent.model)
	Quit:'tPool.%Size() ..Refuse(409, $SELECT(tLive: "No eval case files found", 1: "No recorded agent run to replay for model "_pAgent.model))
	// {"case":"01"} sends that one case (Getting started); it must be in the pool
	If pBody.%Get("case") '= "" {
		Set tCases = [], tPos = tPool.%GetIterator()
		While tPos.%GetNext(, .tId) { Do:tId=pBody.%Get("case") tCases.%Push(tId) }
		Quit:'tCases.%Size() ..Refuse(409, "Case "_pBody.%Get("case")_" has no "_$SELECT(tLive: "case file", 1: "recorded agent run to replay"))
	} Else { Set tCases = ..Pick(tPool, tN) }
	Set tEstimate = $SELECT(tLive: $NORMALIZE(tCases.%Size() * ..AvgCostUsd(pAgent.model), 6), 1: 0)
	If tLive && 'pBody.%Get("confirm") {
		Quit {"ok":false, "status":409, "needsConfirm":true, "error":("A live burst of "_tCases.%Size()_" cases on "_pAgent.model_" costs about $"_tEstimate_"; confirm to send"), "estimatedCostUsd":(tEstimate), "n":(tCases.%Size())}
	}
	Set tSent = [], tSC = $$$OK
	Set tRun = $SELECT(tLive: ..#BURSTLIVERUN, 1: ..#BURSTRUN) + $INCREMENT(^AgenticProd.Flow("burst"))
	Set tIter = tCases.%GetIterator()
	While tIter.%GetNext(, .tCase) {
		Set tControl = "EV"_tRun_"-"_tCase
		Set:'pDryRun tSC = ##class(AgenticProd.Demo).SendCase(tCase, tControl)
		Quit:$$$ISERR(tSC)
		Do tSent.%Push({"case":(tCase), "controlId":(tControl)})
	}
	Quit:$$$ISERR(tSC) ..Refuse(500, $SYSTEM.Status.GetErrorText(tSC))
	Quit {"ok":true, "status":200, "mode":($SELECT(tLive: "live", 1: "replay")), "sent":(tSent), "estimatedCostUsd":(tEstimate), "dryRun":(''pDryRun)}
}

/// 1 when eval run id pRunId belongs to a replay burst: the agent answers it from the recorded run
/// even though its Mode is live.
ClassMethod IsReplayBurst(pRunId As %String) As %Boolean
{
	Quit (pRunId?1.N) && (pRunId >= ..#BURSTRUN) && (pRunId < ..#BURSTLIVERUN)
}

ClassMethod Refuse(pStatus As %Integer, pMessage As %String) As %DynamicObject [ Internal ]
{
	Quit {"ok":false, "status":(pStatus), "error":(pMessage)}
}

/// Case IDs a burst can use: replay needs a recorded live run for the model; live any case file.
ClassMethod CasePool(pLive As %Boolean, pModel As %String) As %DynamicArray
{
	Set tPool = []
	If pLive {
		Set tFile = $ZSEARCH(##class(AgenticProd.Demo).CaseDir()_"*.hl7")
		While tFile '= "" {
			Do tPool.%Push($PIECE(##class(%File).GetFilename(tFile), "-"))
			Set tFile = $ZSEARCH("")
		}
		Quit tPool
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT CaseId FROM AgenticProd_Data.Usage WHERE CaseId IS NOT NULL AND Model = ? AND COALESCE(Replay, 0) = 0 AND DecisionJSON IS NOT NULL", pModel)
	While tRS.%Next() {
		Do:##class(AgenticProd.Demo).CaseFile(tRS.CaseId)'="" tPool.%Push(tRS.CaseId)
	}
	Quit tPool
}

/// pN distinct random members of pPool (all of it when smaller).
ClassMethod Pick(pPool As %DynamicArray, pN As %Integer) As %DynamicArray
{
	Set tPicked = []
	Set tSize = pPool.%Size()
	For i = 0:1:tSize - 1 Set tLeft(i) = pPool.%Get(i)
	While (tPicked.%Size() < pN) && tSize {
		Set tAt = $RANDOM(tSize)
		Do tPicked.%Push(tLeft(tAt))
		Set tLeft(tAt) = tLeft(tSize - 1), tSize = tSize - 1
	}
	Quit tPicked
}

/// Average cost of one real (not replayed) agent run on pModel, the fallback when there is none.
ClassMethod AvgCostUsd(pModel As %String) As %Numeric
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT AVG(CostUsd) AS A FROM AgenticProd_Data.Usage WHERE Model = ? AND COALESCE(Replay, 0) = 0 AND CostUsd > 0", pModel)
	Quit $SELECT(tRS.%Next()&&(tRS.A>0): +tRS.A, 1: ..#FALLBACKCOSTUSD)
}

}
