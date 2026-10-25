/// UI.REST data builders on stub rows, and the /agenticprod web app over HTTP. No LLM.
/// The HTTP tests need Setup.DashboardSetup to have run (web app, reviewer in the dashboard role).
Class AgenticProd.Test.UI.RESTTest Extends %UnitTest.TestCase
{

/// Fake run ID for stub DecisionLog, EvalRun and EvalResult rows.
Parameter RUNID = 999903;

Method TestSummaryCountsOutcomes()
{
	Set tBefore = ##class(AgenticProd.UI.REST).SummaryData()
	Do $$$AssertStatusOK(..AddLogRow(-9301, "AUTO_FIX", "APPLIED"))
	Do $$$AssertStatusOK(..AddLogRow(-9302, "MAP_CODE", "SENT_FOR_APPROVAL"))
	Do $$$AssertStatusOK(..AddLogRow(-9303, "ESCALATE", "DOWNGRADED:AUTO_FIX"))
	Do $$$AssertStatusOK(..AddLogRow(-9304, "MAP_CODE", "APPROVED"))
	Do $$$AssertStatusOK(..AddLogRow(-9305, "REJECT", "REJECTED"))
	Set tAfter = ##class(AgenticProd.UI.REST).SummaryData()
	Do $$$AssertEquals(tAfter.triaged - tBefore.triaged, 5)
	Do $$$AssertEquals(tAfter.autoFixed - tBefore.autoFixed, 1)
	Do $$$AssertEquals(tAfter.sentForApproval - tBefore.sentForApproval, 3, "pending, downgraded and approved all went to a person")
	Do $$$AssertEquals(tAfter.waiting - tBefore.waiting, 2, "approved is no longer waiting")
	Do $$$AssertEquals(tAfter.rejected - tBefore.rejected, 1)
	Do $$$AssertEquals(tAfter.mappingsLearned - tBefore.mappingsLearned, 1)
	Do $$$AssertEquals(tAfter.tokensToday, ##class(AgenticProd.Operation.Agent).TokensUsedToday(), "same count the budget uses")
	Do $$$AssertTrue(tAfter.dailyTokenBudget > 0, "budget from the agent item: "_tAfter.dailyTokenBudget)
	Do $$$AssertTrue(tAfter.traceUrl [ "EnsPortal.VisualTrace.zen?SESSIONID=", tAfter.traceUrl)
}

Method TestDecisionsNewestFirstAndClamped()
{
	Do $$$AssertStatusOK(..AddLogRow(-9311, "AUTO_FIX", "APPLIED"))
	Do $$$AssertStatusOK(..AddLogRow(-9312, "REJECT", "REJECTED"))
	Set tRows = ##class(AgenticProd.UI.REST).DecisionsData(2)
	Do $$$AssertEquals(tRows.%Size(), 2)
	Do $$$AssertEquals(tRows.%Get(0).HeaderId, -9312, "newest first")
	Do $$$AssertEquals(tRows.%Get(0).EvalRunId, ..#RUNID)
	Do $$$AssertEquals(tRows.%GetTypeOf(0), "object")
	Do $$$AssertEquals(tRows.%Get(0).%GetTypeOf("Confidence"), "number")
	Do $$$AssertEquals(tRows.%Get(0).%GetTypeOf("SessionId"), "null", "stub row has no session")
	Set tMax = ##class(AgenticProd.UI.REST).#MAXLIMIT
	Do $$$AssertTrue(##class(AgenticProd.UI.REST).DecisionsData(99999).%Size() <= tMax, "limit capped at "_tMax)
	Do $$$AssertTrue(##class(AgenticProd.UI.REST).DecisionsData("x").%Size() > 0, "bad limit falls back to the default")
}

Method TestEvalRunsAndResults()
{
	Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
	Set tRun.Label = "rest test", tRun.Model = "test", tRun.Mode = "replay", tRun.Status = "DONE"
	Set tRun.Accuracy = .5, tRun.UnsafeAgent = 1, tRun.UnsafeFinal = 0
	Do $$$AssertStatusOK(tRun.%Save())
	Set tRunId = tRun.%Id()
	For tCase = "02", "01" {
		Set tRow = ##class(AgenticProd.Data.EvalResult).%New()
		Set tRow.RunId = tRunId, tRow.CaseId = tCase, tRow.ExpectedDecision = "MAP_CODE"
		Set tRow.AgentDecision = "MAP_CODE", tRow.Acceptable = (tCase = "01"), tRow.UnsafeAgent = 0
		Do $$$AssertStatusOK(tRow.%Save())
	}
	Set tFound = 0, tIter = ##class(AgenticProd.UI.REST).EvalRunsData().%GetIterator()
	While tIter.%GetNext(, .tR) {
		Continue:tR.ID'=tRunId
		Set tFound = 1
		Do $$$AssertEquals(tR.Accuracy, .5)
		Do $$$AssertEquals(tR.UnsafeAgent, 1)
	}
	Do $$$AssertTrue(tFound, "run "_tRunId_" listed")
	Set tCases = ##class(AgenticProd.UI.REST).EvalResultsData(tRunId)
	Do $$$AssertEquals(tCases.%Size(), 2)
	Do $$$AssertEquals(tCases.%Get(0).CaseId, "01", "case order")
	Do $$$AssertEquals(tCases.%Get(0).%GetTypeOf("Acceptable"), "boolean")
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).EvalResultsData(tRunId + 100000), "", "unknown run")
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).EvalResultsData("1 OR 1=1"), "", "non-numeric id")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.EvalResult WHERE RunId = ?", tRunId)
	Do ##class(AgenticProd.Data.EvalRun).%DeleteId(tRunId)
}

/// Reviewer gets JSON and the page; no login and a wrong password get 401; the entry page
/// shows the IRIS login form to an anonymous browser.
Method TestHttpAccess()
{
	Set tUser = ##class(AgenticProd.Setup).#REVIEWUSER, tPass = ##class(AgenticProd.Setup).#REVIEWPASSWORD
	Set tReq = ..Get("api/summary", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "reviewer summary")
	Do $$$AssertTrue(tReq.HttpResponse.ContentType [ "application/json", tReq.HttpResponse.ContentType)
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.%IsDefined("triaged"), "summary has triaged")
	Do $$$AssertEquals(..Get("api/decisions?limit=1", tUser, tPass).HttpResponse.StatusCode, 200)
	Do $$$AssertEquals(..Get("api/evalruns", tUser, tPass).HttpResponse.StatusCode, 200)
	Do $$$AssertEquals(..Get("api/evalruns/0", tUser, tPass).HttpResponse.StatusCode, 404, "unknown run")
	Do $$$AssertEquals(..Get("api/nothing", tUser, tPass).HttpResponse.StatusCode, 404, "unknown route")
	Set tReq = ..Get("dashboard.html", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "page")
	Do $$$AssertTrue(tReq.HttpResponse.ContentType [ "text/html", tReq.HttpResponse.ContentType)
	Do $$$AssertTrue(tReq.HttpResponse.Data.Read(2000) [ "<title>Agentic Production</title>", "page body")
	Do $$$AssertEquals(..Get("api/summary").HttpResponse.StatusCode, 401, "no login")
	Do $$$AssertEquals(..Get("api/summary", tUser, "wrong").HttpResponse.StatusCode, 401, "wrong password")
	Do $$$AssertNotEquals(..Get("dashboard.html").HttpResponse.StatusCode, 200, "no page without login")
}

/// What a browser does: login form on the entry page, post it, then page and API on the
/// session cookies alone (no Basic header), the API through the shared login group.
Method TestBrowserLogin()
{
	Set tUrl = ##class(AgenticProd.Setup).#DASHAPP_"/AgenticProd.UI.Home.cls"
	Set tReq = ##class(%Net.HttpRequest).%New()
	Set tReq.Server = "localhost", tReq.Port = 52773
	Do $$$AssertStatusOK(tReq.Get(tUrl))
	Set tForm = tReq.HttpResponse.Data.Read(32000)
	Do $$$AssertTrue(tForm [ "IRISPassword", "entry page shows the login form")
	// The form carries a one-time token; posting without it is refused
	Set tToken = $PIECE($PIECE($PIECE(tForm, "name=""IRISSessionToken""", 2), "value=""", 2), """")
	Set:tToken="" tToken = $PIECE($PIECE(tForm, """ name=""IRISSessionToken""", 1), "value=""", *)
	Do $$$AssertTrue(tToken '= "", "login token found")
	Do tReq.InsertFormData("IRISUsername", ##class(AgenticProd.Setup).#REVIEWUSER)
	Do tReq.InsertFormData("IRISPassword", ##class(AgenticProd.Setup).#REVIEWPASSWORD)
	Do tReq.InsertFormData("IRISLogin", "Login")
	Do tReq.InsertFormData("IRISSessionToken", tToken)
	Do $$$AssertStatusOK(tReq.Post(tUrl))
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 302, "login accepted")
	Do $$$AssertStatusOK(tReq.Get(##class(AgenticProd.Setup).#DASHAPP_"/dashboard.html"))
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "page after login")
	Do $$$AssertStatusOK(tReq.Get(##class(AgenticProd.Setup).#DASHAPI_"/summary"))
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "API on the page's login")
}

Method Get(pPath As %String, pUser As %String = "", pPass As %String = "") As %Net.HttpRequest
{
	Set tReq = ##class(%Net.HttpRequest).%New()
	Set tReq.Server = "localhost", tReq.Port = 52773
	Set:pUser'="" tReq.Username = pUser, tReq.Password = pPass
	Do $$$AssertStatusOK(tReq.Get(##class(AgenticProd.Setup).#DASHAPP_"/"_pPath), "GET "_pPath)
	Quit tReq
}

Method AddLogRow(pHeader As %Integer, pDecision As %String, pOutcome As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tRow.HeaderId = pHeader, tRow.Decision = pDecision, tRow.ErrorClass = "OTHER"
	Set tRow.EvalRunId = ..#RUNID, tRow.CaseId = "T", tRow.Outcome = pOutcome, tRow.Confidence = .5
	Quit tRow.%Save()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE EvalRunId = ?", ..#RUNID)
	Quit $$$OK
}

}
