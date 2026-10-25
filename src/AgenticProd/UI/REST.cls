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
		Write ..SummaryData().%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod Decisions() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..DecisionsData(%request.Get("limit", ..#DEFAULTLIMIT)).%ToJSON()
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

/// KPI tiles. Counts are over all of DecisionLog; cost and tokens are for today (UTC, like
/// Operation.Agent's budget). costPerMessage is over every live agent run, replays excluded.
ClassMethod SummaryData() As %DynamicObject
{
	Set tLog = ..Rows("SELECT COUNT(DISTINCT HeaderId) AS Triaged,"
		_" SUM(CASE WHEN Outcome = 'APPLIED' THEN 1 ELSE 0 END) AS AutoFixed,"
		_" SUM(CASE WHEN Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:' OR Outcome = 'APPROVED' OR Outcome %STARTSWITH 'REVIEW_' THEN 1 ELSE 0 END) AS SentForApproval,"
		_" SUM(CASE WHEN Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:' THEN 1 ELSE 0 END) AS Waiting,"
		_" SUM(CASE WHEN Outcome = 'REJECTED' THEN 1 ELSE 0 END) AS Rejected,"
		_" SUM(CASE WHEN Outcome = 'APPROVED' THEN 1 ELSE 0 END) AS MappingsLearned"
		_" FROM AgenticProd_Data.DecisionLog").%Get(0)
	Set tToday = $ZDATE($PIECE($ZTIMESTAMP, ","), 3)_" 00:00:00"
	// Replay rows repeat a recorded cost; counting them would bill the same run twice
	Set tLive = "(Replay = 0 OR Replay IS NULL)"
	Set tDay = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE CreatedAt >= ? AND "_tLive, tToday).%Get(0)
	Set tAll = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE "_tLive).%Get(0)
	Set tItem = ##class(AgenticProd.Eval.Runner).#AGENTITEM
	Set tBudget = ##class(Ens.Director).GetHostSettingValue(tItem, "DailyTokenBudget", .tSC)
	// Not in the production file means the property's InitialExpression applies
	Set:$$$ISERR(tSC)||(tBudget="") tBudget = ##class(%Dictionary.CompiledProperty).%OpenId("AgenticProd.Operation.Agent||DailyTokenBudget").InitialExpression
	Set tOut = {
		"triaged": (+tLog.Triaged), "autoFixed": (+tLog.AutoFixed),
		"sentForApproval": (+tLog.SentForApproval), "waiting": (+tLog.Waiting),
		"rejected": (+tLog.Rejected), "mappingsLearned": (+tLog.MappingsLearned),
		"costToday": (+tDay.Cost), "agentRunsToday": (+tDay.Runs),
		"costPerMessage": ($SELECT(tAll.Runs: $NORMALIZE(tAll.Cost / tAll.Runs, 6), 1: "")),
		"tokensToday": (##class(AgenticProd.Operation.Agent).TokensUsedToday()),
		"dailyTokenBudget": (+tBudget),
		"traceUrl": ($SYSTEM.CSP.GetDefaultApp($NAMESPACE)_"/EnsPortal.VisualTrace.zen?SESSIONID=")
	}
	Do:tOut.costPerMessage="" tOut.%Set("costPerMessage", "", "null")
	Quit tOut
}

/// Latest pLimit DecisionLog rows, newest first. pLimit is clamped to 1..MAXLIMIT.
ClassMethod DecisionsData(pLimit As %Integer = {..#DEFAULTLIMIT}) As %DynamicArray
{
	Set pLimit = pLimit \ 1
	Set:pLimit<1 pLimit = ..#DEFAULTLIMIT
	Set:pLimit>..#MAXLIMIT pLimit = ..#MAXLIMIT
	Quit ..Rows("SELECT TOP ? ID, CreatedAt, EvalRunId, CaseId, HeaderId, SessionId, Source, ErrorClass, Decision, Outcome, Confidence, CostUsd, Model"
		_" FROM AgenticProd_Data.DecisionLog ORDER BY ID DESC", pLimit)
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
