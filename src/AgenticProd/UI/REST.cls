/// Read-only JSON for the dashboard page (web/dashboard.html), served at /agenticprod/api.
/// The page app /agenticprod does the login; both apps share one login group (Setup.DashboardSetup).
/// The *Data methods build the JSON so tests can call them without HTTP.
Class AgenticProd.UI.REST Extends %CSP.REST
{

Parameter CHARSET = "utf-8";

Parameter CONTENTTYPE = "application/json";

Parameter HandleCorsRequest = 0;

/// The login comes from the page app's session (same login group); without a session here
/// that login is not picked up and every call is a 401.
Parameter UseSession = 1;

/// Recent decisions returned when the page does not ask for a limit; MAXLIMIT caps a request.
Parameter DEFAULTLIMIT = 50;

Parameter MAXLIMIT = 200;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/summary" Method="GET" Call="Summary"/>
<Route Url="/decisions" Method="GET" Call="Decisions"/>
<Route Url="/evalruns" Method="GET" Call="EvalRuns"/>
<Route Url="/evalruns/:id" Method="GET" Call="EvalResults"/>
</Routes>
}

ClassMethod Summary() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..SummaryData(''%request.Get("eval")).%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod Decisions() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..DecisionsData(%request.Get("limit", ..#DEFAULTLIMIT), ''%request.Get("eval")).%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod EvalRuns() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..EvalRunsData().%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod EvalResults(pRunId As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tData = ..EvalResultsData(pRunId)
		If '$IsObject(tData) {
			Set %response.Status = ..#HTTP404NOTFOUND
			Write {"error":("no eval run "_pRunId)}.%ToJSON()
			Quit
		}
		Write tData.%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// KPI tiles. Live traffic only unless pIncludeEval (eval messages carry EvalRunId, from their
/// EV* control ID). Counts are over all of DecisionLog; cost is for today (UTC, like
/// Operation.Agent's budget). costPerMessage covers the agent item's current Model only,
/// replays excluded. Tokens are the budget's own count, eval included, since the budget
/// stops eval and live traffic alike.
ClassMethod SummaryData(pIncludeEval As %Boolean = 0) As %DynamicObject
{
	Set tLogWhere = $SELECT(pIncludeEval: "", 1: " WHERE EvalRunId IS NULL")
	Set tLog = ..Rows("SELECT COUNT(DISTINCT HeaderId) AS Triaged,"
		_" SUM(CASE WHEN Outcome = 'APPLIED' THEN 1 ELSE 0 END) AS AutoFixed,"
		_" SUM(CASE WHEN Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:' OR Outcome = 'APPROVED' OR Outcome %STARTSWITH 'REVIEW_' THEN 1 ELSE 0 END) AS SentForApproval,"
		_" SUM(CASE WHEN (Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:') AND ReviewedAt IS NULL THEN 1 ELSE 0 END) AS Waiting,"
		_" SUM(CASE WHEN Outcome = 'REJECTED' THEN 1 ELSE 0 END) AS Rejected,"
		_" SUM(CASE WHEN Outcome = 'APPROVED' THEN 1 ELSE 0 END) AS MappingsLearned"
		_" FROM AgenticProd_Data.DecisionLog"_tLogWhere).%Get(0)
	// Triage marks its own changes DOWNGRADED:X; an ESCALATE over a different agent proposal counts too
	Set tChanged = ..Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog d WHERE (d.Outcome %STARTSWITH 'DOWNGRADED:'"
		_" OR (d.Decision = 'ESCALATE' AND EXISTS (SELECT 1 FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Decision <> 'ESCALATE')))"
		_$SELECT(pIncludeEval: "", 1: " AND d.EvalRunId IS NULL")).%Get(0)
	Set tToday = $ZDATE($PIECE($ZTIMESTAMP, ","), 3)_" 00:00:00"
	// Replay rows repeat a recorded cost; counting them would bill the same run twice
	Set tLive = "(Replay = 0 OR Replay IS NULL)"_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL")
	Set tDay = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE CreatedAt >= ? AND "_tLive, tToday).%Get(0)
	Set tItem = ##class(AgenticProd.Eval.Runner).#AGENTITEM
	Set tModel = ..AgentSetting(tItem, "Model")
	Set tByModel = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE Model = ? AND "_tLive, tModel).%Get(0)
	Set tBudget = +..AgentSetting(tItem, "DailyTokenBudget")
	Set tTokens = ##class(AgenticProd.Operation.Agent).TokensUsedToday()
	Set tOut = {
		"includeEval": (''pIncludeEval),
		"triaged": (+tLog.Triaged), "autoFixed": (+tLog.AutoFixed),
		"sentForApproval": (+tLog.SentForApproval), "waiting": (+tLog.Waiting),
		"rejected": (+tLog.Rejected), "mappingsLearned": (+tLog.MappingsLearned),
		"changedByTriage": (+tChanged.N),
		"costToday": (+tDay.Cost), "agentRunsToday": (+tDay.Runs),
		"model": (tModel), "agentRunsModel": (+tByModel.Runs),
		"costPerMessage": ($SELECT(tByModel.Runs: $NORMALIZE(tByModel.Cost / tByModel.Runs, 6), 1: "")),
		"tokensToday": (tTokens), "dailyTokenBudget": (tBudget),
		"tokensPercent": ($SELECT(tBudget: $NORMALIZE(tTokens / tBudget * 100, 0), 1: "")),
		"overBudget": (tBudget && (tTokens >= tBudget)),
		"traceUrl": ($SYSTEM.CSP.GetDefaultApp($NAMESPACE)_"/EnsPortal.VisualTrace.zen?SESSIONID=")
	}
	Do tOut.%Set("includeEval", tOut.includeEval, "boolean"), tOut.%Set("overBudget", tOut.overBudget, "boolean")
	For tKey = "costPerMessage", "tokensPercent" Do:tOut.%Get(tKey)="" tOut.%Set(tKey, "", "null")
	Quit tOut
}

/// Latest pLimit DecisionLog rows, newest first; live traffic only unless pIncludeEval.
/// pLimit is clamped to 1..MAXLIMIT. Besides the log columns each row has AgentDecision (what the
/// agent sent Triage), triageChanged, flagged (InjectionGuard field refs, [] when none),
/// agentCalled and, when no agent run is recorded, noAgentReason: loop guard, budget, replay,
/// agent error, or "" when the reason is not known.
ClassMethod DecisionsData(pLimit As %Integer = {..#DEFAULTLIMIT}, pIncludeEval As %Boolean = 0) As %DynamicArray
{
	Set pLimit = pLimit \ 1
	Set:pLimit<1 pLimit = ..#DEFAULTLIMIT
	Set:pLimit>..#MAXLIMIT pLimit = ..#MAXLIMIT
	Set tRows = ..Rows("SELECT TOP ? d.ID, d.CreatedAt, d.EvalRunId, d.CaseId, d.HeaderId, d.SessionId, d.Source, d.ErrorClass, d.Decision, d.Outcome, d.Confidence, d.CostUsd, d.Model, d.Reason, d.DecisionJSON,"
		_" (SELECT MAX(u.Decision) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId) AS AgentDecision,"
		_" (SELECT COUNT(*) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND (u.Replay = 0 OR u.Replay IS NULL)) AS AgentCalls,"
		_" (SELECT COUNT(*) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Replay = 1) AS Replays"
		_" FROM AgenticProd_Data.DecisionLog d"_$SELECT(pIncludeEval: "", 1: " WHERE d.EvalRunId IS NULL")_" ORDER BY d.ID DESC", pLimit)
	Set tIter = tRows.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Set tFlags = []
		Set tDecision = $SELECT(tRow.DecisionJSON '= "": ##class(%DynamicObject).%FromJSON(tRow.DecisionJSON), 1: {})
		If $IsObject(tDecision.evidence) {
			// Triage.Plan adds "suspicious instruction in <ref>: <matched text>" per InjectionGuard flag
			Set tEv = tDecision.evidence.%GetIterator()
			While tEv.%GetNext(, .tLine) {
				Do:$EXTRACT(tLine, 1, 26)="suspicious instruction in " tFlags.%Push($PIECE($EXTRACT(tLine, 27, *), ": "))
			}
		}
		Do tRow.%Set("flagged", tFlags)
		Set tChanged = ($EXTRACT(tRow.Outcome, 1, 11) = "DOWNGRADED:") || ((tRow.Decision = "ESCALATE") && (tRow.AgentDecision '= "") && (tRow.AgentDecision '= "ESCALATE"))
		Do tRow.%Set("triageChanged", tChanged, "boolean")
		Do tRow.%Set("agentCalled", tRow.AgentCalls > 0, "boolean")
		If tRow.AgentCalls = 0 {
			// "agent error": runs from before failed runs got a Usage row (Operation.Agent)
			Set tWhy = $SELECT(tRow.Replays: "replay", tRow.Reason [ "agent not called a second time": "loop guard",
				tRow.Reason [ "Daily token budget": "budget", tRow.Reason [ "agent gave no decision": "agent error", 1: "")
			Do tRow.%Set("noAgentReason", tWhy)
		}
		For tKey = "DecisionJSON", "Reason", "AgentCalls", "Replays" Do tRow.%Remove(tKey)
	}
	Quit tRows
}

/// Agent production item setting; the property's InitialExpression when the production file
/// does not set it.
ClassMethod AgentSetting(pItem As %String, pName As %String) As %String [ Internal ]
{
	Set tValue = ##class(Ens.Director).GetHostSettingValue(pItem, pName, .tSC)
	Quit:$$$ISOK(tSC)&&(tValue'="") tValue
	Set tProp = ##class(%Dictionary.CompiledProperty).%OpenId("AgenticProd.Operation.Agent||"_pName)
	Quit $SELECT($IsObject(tProp): $ZSTRIP(tProp.InitialExpression, "<>", """"), 1: "")
}

ClassMethod EvalRunsData() As %DynamicArray
{
	Quit ..Rows("SELECT ID, Label, Model, Mode, Status, StartedAt, CaseCount, Accuracy, ExactAccuracy, MappingAccuracy,"
		_" UnsafeAgent, UnsafeFinal, TimedOut, CostPerMessageUsd, P95Seconds FROM AgenticProd_Data.EvalRun ORDER BY ID DESC")
}

/// Per-case rows of run pRunId, or "" when there is no such run.
ClassMethod EvalResultsData(pRunId As %String) As %DynamicArray
{
	Quit:(pRunId'?1.N)||'##class(AgenticProd.Data.EvalRun).%ExistsId(pRunId) ""
	Quit ..Rows("SELECT CaseId, Slug, CaseGroup, ExpectedDecision, AgentDecision, ExpectedLoinc, AgentLoinc, FinalDecision, FinalOutcome,"
		_" Acceptable, Exact, UnsafeAgent, UnsafeFinal, Injection, InjectionFlagged, Seconds, CostUsd, AgentSessionId"
		_" FROM AgenticProd_Data.EvalResult WHERE RunId = ? ORDER BY CaseId", pRunId)
}

/// Rows of pSQL as JSON objects keyed by column name, typed from the column's client type
/// so numbers and booleans are not sent as strings. Throws on SQL errors.
ClassMethod Rows(pSQL As %String, pArgs...) As %DynamicArray
{
	Set tStmt = ##class(%SQL.Statement).%New()
	$$$ThrowOnError(tStmt.%Prepare(pSQL))
	Set tRS = tStmt.%Execute(pArgs...)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Set tCols = tStmt.%Metadata.columns, tN = tCols.Count()
	For i = 1:1:tN Set tName(i) = tCols.GetAt(i).colName, tType(i) = tCols.GetAt(i).clientType
	Set tRows = []
	While tRS.%Next() {
		Set tRow = {}
		For i = 1:1:tN {
			Set tVal = tRS.%GetData(i)
			If tVal = "" {
				Do tRow.%Set(tName(i), "", "null")
			} ElseIf tType(i) = 16 {
				Do tRow.%Set(tName(i), tVal, "boolean")
			} ElseIf ",3,5,14,15,18," [ (","_tType(i)_",") {
				Do tRow.%Set(tName(i), +tVal, "number")
			} Else {
				Do tRow.%Set(tName(i), tVal)
			}
		}
		Do tRows.%Push(tRow)
	}
	Quit tRows
}

}
