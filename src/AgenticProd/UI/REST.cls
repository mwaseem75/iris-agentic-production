/// JSON for the dashboard page (web/dashboard.html), served at /agenticprod/api. Read-only
/// except /settings writes, which need the AgenticProd_Admin role (Settings.Store).
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

/// Seconds without a new EvalResult after which a RUNNING eval run is shown as STOPPED.
Parameter STALESECONDS = 600;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/summary" Method="GET" Call="Summary"/>
<Route Url="/decisions" Method="GET" Call="Decisions"/>
<Route Url="/decisions/:id/story" Method="GET" Call="Story"/>
<Route Url="/metrics/summary" Method="GET" Call="Metrics"/>
<Route Url="/evalruns" Method="GET" Call="EvalRuns"/>
<Route Url="/evalruns/:id" Method="GET" Call="EvalResults"/>
<Route Url="/cost/summary" Method="GET" Call="Cost"/>
<Route Url="/settings" Method="GET" Call="Settings"/>
<Route Url="/settings/productions" Method="GET" Call="SettingsProductions"/>
<Route Url="/settings/productions/:action" Method="POST" Call="SettingsProduction"/>
<Route Url="/settings/key" Method="POST" Call="SettingsKey"/>
<Route Url="/settings/test-connection" Method="POST" Call="SettingsTest"/>
<Route Url="/settings/kill-switch" Method="POST" Call="SettingsKillSwitch"/>
<Route Url="/settings/memory/revoke" Method="POST" Call="SettingsRevoke"/>
<Route Url="/settings/:section" Method="PUT" Call="SettingsSave"/>
</Routes>
}

ClassMethod Settings() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..SettingsData().%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Everything the Settings tab shows. Keys appear only as "set" / "not set".
/// canEdit tells the page whether to offer the forms; every write checks it again.
ClassMethod SettingsData() As %DynamicObject
{
	Set tData = {"user":($USERNAME)}
	Do tData.%Set("canEdit", ..CanEditSettings(), "boolean")
	Set tData.providerKinds = [], tData.compatKinds = []
	Set tKinds = ##class(AgenticProd.Settings.Store).#PROVIDERS
	For i = 1:1:$LENGTH(tKinds, ",") Do tData.providerKinds.%Push($PIECE(tKinds, ",", i))
	Set tKinds = ##class(AgenticProd.Settings.Store).#COMPATKINDS
	For i = 1:1:$LENGTH(tKinds, ",") Do tData.compatKinds.%Push($PIECE(tKinds, ",", i))
	Set tData.providers = ##class(AgenticProd.Settings.Store).Providers()
	Set tData.agents = ##class(AgenticProd.Settings.Store).ItemSettings(##class(AgenticProd.Settings.Store).#AGENTFIELDS)
	Set tData.skills = ##class(AgenticProd.Settings.Store).Skills()
	Set tData.instructions = ##class(AgenticProd.Settings.Store).XDataText("AgenticProd.Agent.TriageAgent", "INSTRUCTIONS")
	Set tData.guardrails = ##class(AgenticProd.Settings.Store).ItemSettings(##class(AgenticProd.Settings.Store).#GUARDFIELDS)
	Set tData.errorClasses = []
	Set tKinds = $EXTRACT(##class(AgenticProd.Msg.ErrorClass).#VALUELIST, 2, *)
	For i = 1:1:$LENGTH(tKinds, ",") Do tData.errorClasses.%Push($PIECE(tKinds, ",", i))
	// The catalog needs an agent %Init; a broken provider must not hide the rest of the page
	Try {
		Set tData.tools = ##class(AgenticProd.Settings.Store).Tools()
	} Catch ex {
		Set tData.tools = [], tData.toolsError = $SYSTEM.Status.GetErrorText(ex.AsStatus())
	}
	Set tData.budgets = ##class(AgenticProd.Settings.Store).ItemSettings(##class(AgenticProd.Settings.Store).#BUDGETFIELDS)
	Do tData.budgets.%Set("KillSwitch", +tData.budgets.KillSwitch, "boolean")
	Set tData.usedToday = ##class(AgenticProd.Operation.Agent).TokensUsedToday()
	Set tData.prices = ##class(AgenticProd.Settings.Store).Prices()
	Do tData.budgets.%Set("MinutesPerFailure", ##class(AgenticProd.UI.Cost).RoiSetting("MinutesPerFailure"), "number")
	Do tData.budgets.%Set("EngineerHourlyRate", ##class(AgenticProd.UI.Cost).RoiSetting("EngineerHourlyRate"), "number")
	Set tData.budgets.currency = ##class(AgenticProd.UI.Cost).#CURRENCY
	Set tData.memory = ##class(AgenticProd.Settings.Store).Memory()
	Set tData.changes = ##class(AgenticProd.Settings.Store).ChangeLog(50)
	Quit tData
}

ClassMethod CanEditSettings() As %Boolean
{
	Quit $SYSTEM.Security.Check(##class(AgenticProd.Settings.Store).#EDITRESOURCE, "WRITE")
}

/// PUT /settings/providers|agents|guardrails|budgets|prices with the section's fields as JSON.
ClassMethod SettingsSave(pSection As %String) As %Status
{
	Quit ..SettingsWrite(pSection)
}

/// POST /settings/key {"name":..., "key":...}. The response never echoes the key.
ClassMethod SettingsKey() As %Status
{
	Quit ..SettingsWrite("key")
}

/// POST /settings/test-connection {"name":..., "model":...}: one real LLM call.
ClassMethod SettingsTest() As %Status
{
	Quit ..SettingsWrite("test")
}

/// POST /settings/kill-switch {"on":true|false}
ClassMethod SettingsKillSwitch() As %Status
{
	Quit ..SettingsWrite("kill-switch")
}

/// Productions with the plug-in, the home production and candidates (Plugin.Installer.Productions).
ClassMethod SettingsProductions() As %Status
{
	Set tSC = $$$OK
	Try {
		Set tOut = {"productions":(##class(AgenticProd.Plugin.Installer).Productions()), "modes":[]}
		Do tOut.%Set("canEdit", ..CanEditSettings(), "boolean")
		Set tModes = ##class(AgenticProd.Plugin.Installer).#MODES
		For i = 1:1:$LENGTH(tModes, ",") Do tOut.modes.%Push($PIECE(tModes, ",", i))
		Write tOut.%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// POST /settings/productions/enable|disable|mode {"namespace", "production", "mode",
/// "codeTable", "codeTableFormat"}
ClassMethod SettingsProduction(pAction As %String) As %Status
{
	Quit ..SettingsWrite("production-"_pAction)
}

/// POST /settings/memory/revoke {"id":..., "reason":...}
ClassMethod SettingsRevoke() As %Status
{
	Quit ..SettingsWrite("revoke")
}

/// Role check, body parse and dispatch for every settings write. A refused or invalid change
/// answers 403 / 400 with the reason, not a 500.
ClassMethod SettingsWrite(pAction As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		If '..CanEditSettings() {
			Set %response.Status = ..#HTTP403FORBIDDEN
			Write {"error":"Changing settings needs the AgenticProd_Admin role"}.%ToJSON()
			Quit
		}
		Try {
			Set tBody = {}.%FromJSON(%request.Content)
		} Catch {
			Set tBody = ""
		}
		If '$IsObject(tBody) {
			Set %response.Status = ..#HTTP400BADREQUEST
			Write {"error":"Body must be a JSON object"}.%ToJSON()
			Quit
		}
		Set tResult = ..SettingsApply(pAction, tBody, .tWriteSC)
		If $$$ISERR(tWriteSC) {
			Set %response.Status = ..#HTTP400BADREQUEST
			Write {"error":($SYSTEM.Status.GetErrorText(tWriteSC))}.%ToJSON()
			Quit
		}
		Write tResult.%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// The write itself, without HTTP, so tests can call it. pSC is the store's status.
ClassMethod SettingsApply(pAction As %String, pBody As %DynamicObject, Output pSC As %Status) As %DynamicObject
{
	Set tResult = {"ok":true}
	If pAction = "providers" {
		Set pSC = ##class(AgenticProd.Settings.Store).SaveProvider(pBody)
	} ElseIf (pAction = "agents") || (pAction = "guardrails") || (pAction = "budgets") {
		Set pSC = ##class(AgenticProd.Settings.Store).SaveItemSettings(pAction, pBody, .tNote)
	} ElseIf pAction = "prices" {
		Set pSC = ##class(AgenticProd.Settings.Store).SavePrice(pBody)
	} ElseIf pAction = "key" {
		Set pSC = ##class(AgenticProd.Settings.Store).SetKey(pBody.%Get("name"), pBody.%Get("key"))
		Set:$$$ISOK(pSC) tResult.key = ##class(AgenticProd.Settings.Store).KeyStatus(pBody.%Get("name"))
	} ElseIf pAction = "kill-switch" {
		Set pSC = ##class(AgenticProd.Settings.Store).SetKillSwitch(''pBody.%Get("on"), .tNote)
	} ElseIf pAction = "revoke" {
		Set pSC = ##class(AgenticProd.Settings.Store).RevokeMapping(pBody.%Get("id"), pBody.%Get("reason"), .tNote)
	} ElseIf pAction = "production-enable" {
		Set tTable = pBody.%Get("codeTable"), tFormat = pBody.%Get("codeTableFormat")
		Set pSC = ##class(AgenticProd.Plugin.Installer).Enable(pBody.%Get("namespace"), pBody.%Get("production"), $SELECT(pBody.%Get("mode") '= "": pBody.%Get("mode"), 1: "observe"), .tAdded, , $SELECT(tTable '= "": tTable, 1: "LabCodeMap"), $SELECT(tFormat '= "": tFormat, 1: "loinc^display"))
		Set:$$$ISOK(pSC) tNote = $SELECT(tAdded '= "": "Added "_tAdded, 1: "Already enabled")
	} ElseIf pAction = "production-disable" {
		Set pSC = ##class(AgenticProd.Plugin.Installer).Disable(pBody.%Get("namespace"), pBody.%Get("production"), .tRemoved)
		Set:$$$ISOK(pSC) tNote = $SELECT(tRemoved '= "": "Removed "_tRemoved, 1: "Nothing to remove")
	} ElseIf pAction = "production-mode" {
		Set pSC = ##class(AgenticProd.Plugin.Installer).SetMode(pBody.%Get("namespace"), pBody.%Get("production"), pBody.%Get("mode"), .tNote)
	} ElseIf pAction = "test" {
		Set pSC = ##class(AgenticProd.Settings.Store).TestConnection(pBody.%Get("name"), pBody.%Get("model"), .tResult)
	} Else {
		Set pSC = $$$ERROR($$$GeneralError, "Unknown settings section "_pAction)
	}
	Set:$GET(tNote)'="" tResult.note = tNote
	Quit tResult
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
		Write ..DecisionsData(%request.Get("limit", ..#DEFAULTLIMIT), ''%request.Get("eval"), %request.Get("ns")).%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod Story(pId As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tData = ..StoryData(pId)
		If '$IsObject(tData) {
			Set %response.Status = ..#HTTP404NOTFOUND
			Write {"error":("no decision "_pId)}.%ToJSON()
			Quit
		}
		Write tData.%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod Metrics() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ..MetricsData(''%request.Get("eval")).%ToJSON()
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
		_" SUM(CASE WHEN Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:' OR Outcome %STARTSWITH 'PROPOSED:' OR Outcome = 'APPROVED' OR Outcome %STARTSWITH 'REVIEW_' THEN 1 ELSE 0 END) AS SentForApproval,"
		_" SUM(CASE WHEN (Outcome = 'SENT_FOR_APPROVAL' OR Outcome %STARTSWITH 'DOWNGRADED:' OR Outcome %STARTSWITH 'PROPOSED:') AND ReviewedAt IS NULL THEN 1 ELSE 0 END) AS Waiting,"
		_" SUM(CASE WHEN Outcome = 'REJECTED' THEN 1 ELSE 0 END) AS Rejected,"
		_" SUM(CASE WHEN Outcome = 'APPROVED' THEN 1 ELSE 0 END) AS MappingsLearned,"
		_" SUM(CASE WHEN Grounded = 1 THEN 1 ELSE 0 END) AS GroundingPassed,"
		_" SUM(CASE WHEN Grounded = 0 THEN 1 ELSE 0 END) AS GroundingCaught"
		_" FROM AgenticProd_Data.DecisionLog"_tLogWhere).%Get(0)
	// Triage marks its own changes DOWNGRADED:X; an ESCALATE over a different agent proposal counts too
	Set tChanged = ..Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog d WHERE (d.Outcome %STARTSWITH 'DOWNGRADED:'"
		_" OR (d.Decision = 'ESCALATE' AND EXISTS (SELECT 1 FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Namespace = d.Namespace AND u.Decision <> 'ESCALATE')))"
		_$SELECT(pIncludeEval: "", 1: " AND d.EvalRunId IS NULL")).%Get(0)
	Set tToday = $ZDATE($PIECE($ZTIMESTAMP, ","), 3)_" 00:00:00"
	// Replay rows repeat a recorded cost; counting them would bill the same run twice
	Set tLive = "(Replay = 0 OR Replay IS NULL)"_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL")
	Set tDay = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE CreatedAt >= ? AND "_tLive, tToday).%Get(0)
	Set tItem = ##class(AgenticProd.Eval.Runner).#AGENTITEM
	Set tModel = ..AgentSetting(tItem, "Model")
	Set tByModel = ..Rows("SELECT SUM(CostUsd) AS Cost, COUNT(*) AS Runs FROM AgenticProd_Data.Usage WHERE Model = ? AND "_tLive, tModel).%Get(0)
	Set tBudget = +..AgentSetting(tItem, "DailyTokenBudget")
	// Eval sends carry MSH-10 EV<runId>-<caseId>; rows from before ControlId was stored count as live
	Set tFHIR = ..Rows("SELECT SUM(CASE WHEN Valid = 1 THEN 1 ELSE 0 END) AS Valid, SUM(CASE WHEN Valid = 1 THEN 0 ELSE 1 END) AS Invalid"
		_" FROM AgenticProd_Msg.FHIRResult"_$SELECT(pIncludeEval: "", 1: " WHERE ControlId IS NULL OR ControlId NOT LIKE 'EV%-%'")).%Get(0)
	Set tTokens = ##class(AgenticProd.Operation.Agent).TokensUsedToday()
	Set tOut = {
		"includeEval": (''pIncludeEval),
		"triaged": (+tLog.Triaged), "autoFixed": (+tLog.AutoFixed),
		"sentForApproval": (+tLog.SentForApproval), "waiting": (+tLog.Waiting),
		"rejected": (+tLog.Rejected), "mappingsLearned": (+tLog.MappingsLearned),
		"groundingPassed": (+tLog.GroundingPassed), "groundingCaught": (+tLog.GroundingCaught),
/// GET /cost/summary?eval=&days=
ClassMethod Cost() As %Status
{
	Set tSC = $$$OK
	Try {
		Write ##class(AgenticProd.UI.Cost).Data(''%request.Get("eval"), %request.Get("days", 30)).%ToJSON()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

		"changedByTriage": (+tChanged.N),
		"fhirValid": (+tFHIR.Valid), "fhirInvalid": (+tFHIR.Invalid),
		"costToday": (+tDay.Cost), "agentRunsToday": (+tDay.Runs),
		"model": (tModel), "agentRunsModel": (+tByModel.Runs),
		"costPerMessage": ($SELECT(tByModel.Runs: $NORMALIZE(tByModel.Cost / tByModel.Runs, 6), 1: "")),
		"tokensToday": (tTokens), "dailyTokenBudget": (tBudget),
		"tokensPercent": ($SELECT(tBudget: $NORMALIZE(tTokens / tBudget * 100, 0), 1: "")),
		"overBudget": (tBudget && (tTokens >= tBudget)),
		"traceUrl": (..TraceUrl()),
		"productionUrl": ($SYSTEM.CSP.GetDefaultApp($NAMESPACE)_"/EnsPortal.ProductionConfig.zen?PRODUCTION="_##class(AgenticProd.Production).%ClassName(1)),
		// the portal's Workflow Inbox menu entry opens this User Portal page
		"inboxUrl": ($SYSTEM.CSP.GetDefaultApp($NAMESPACE)_"/_DeepSee.UserPortal.Workflow.zen")
	}
	Do tOut.%Set("includeEval", tOut.includeEval, "boolean"), tOut.%Set("overBudget", tOut.overBudget, "boolean")
	// Every tab shows a banner while it is on
	Do tOut.%Set("killSwitch", +..AgentSetting(tItem, "KillSwitch"), "boolean")
	For tKey = "costPerMessage", "tokensPercent" Do:tOut.%Get(tKey)="" tOut.%Set(tKey, "", "null")
	Quit tOut
}

/// Latest pLimit DecisionLog rows, newest first; live traffic only unless pIncludeEval.
/// pLimit is clamped to 1..MAXLIMIT. Besides the log columns each row has AgentDecision (what the
/// agent sent Triage), triageChanged, flagged (InjectionGuard field refs, [] when none),
/// agentCalled and, when no agent run is recorded, noAgentReason: loop guard, budget, replay,
/// agent error, or "" when the reason is not known. pNamespace: only that production's rows.
ClassMethod DecisionsData(pLimit As %Integer = {..#DEFAULTLIMIT}, pIncludeEval As %Boolean = 0, pNamespace As %String = "") As %DynamicArray
{
	Set pLimit = pLimit \ 1
	Set:pLimit<1 pLimit = ..#DEFAULTLIMIT
	Set:pLimit>..#MAXLIMIT pLimit = ..#MAXLIMIT
	// TriageRequest bodies are messages, local to each namespace: only this one's can be joined
	Set tRows = ..Rows("SELECT TOP ? d.ID, d.CreatedAt, d.EvalRunId, d.CaseId, d.HeaderId, d.SessionId, d.Namespace, d.Source, d.ErrorClass, d.Decision, d.Outcome, d.Confidence, d.CostUsd, d.Model, d.Reason, d.DecisionJSON,"
		_" CASE WHEN d.Namespace = ? THEN (SELECT MAX(t.ControlId) FROM AgenticProd_Msg.TriageRequest t WHERE t.HeaderId = d.HeaderId) END AS ControlId,"
		_" (SELECT MAX(u.Decision) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Namespace = d.Namespace) AS AgentDecision,"
		_" (SELECT COUNT(*) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Namespace = d.Namespace AND (u.Replay = 0 OR u.Replay IS NULL)) AS AgentCalls,"
		_" (SELECT COUNT(*) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Namespace = d.Namespace AND u.Replay = 1) AS Replays"
		_" FROM AgenticProd_Data.DecisionLog d WHERE (? IS NULL OR d.Namespace = ?)"_$SELECT(pIncludeEval: "", 1: " AND d.EvalRunId IS NULL")_" ORDER BY d.ID DESC", pLimit, $NAMESPACE, pNamespace, pNamespace)
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
				tRow.Reason [ "Daily token budget": "budget", tRow.Reason [ "agent gave no decision": "agent error",
				tRow.Reason [ "no fix checker for format": "no checker for format", 1: "")
			Do tRow.%Set("noAgentReason", tWhy)
		}
		Do tRow.%Set("fhirOut", ..FHIRStatus(tRow.SessionId, tRow.Namespace))
		Do tRow.%Set("traceUrl", ..TraceUrl(tRow.Namespace))
		For tKey = "DecisionJSON", "Reason", "AgentCalls", "Replays" Do tRow.%Remove(tKey)
	}
	Quit tRows
}

/// What happened to DecisionLog row pId, as plain-language steps for a reader who is not an
/// integration engineer: router check, injection check, agent and its tool calls, the Triage rule,
/// and the review. Also the Data.Span rows of the message's latest trace and the masked message
/// text. "" when there is no such row. Text from the message or the agent goes through Mask first.
ClassMethod StoryData(pId As %String) As %DynamicObject
{
	Quit:(pId'?1.N)||'##class(AgenticProd.Data.DecisionLog).%ExistsId(pId) ""
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pId)
	Set tNS = tLog.Namespace
	Set tMessage = ..MaskedMessage(tLog.HeaderId, .tSecrets, tNS)
	Set tTrace = ..Rows("SELECT TOP 1 TraceId FROM AgenticProd_Data.Span WHERE HeaderId = ? AND Namespace = ? ORDER BY ID DESC", tLog.HeaderId, tNS).%Get(0)
	// Root first: the review span starts at DecisionLog.CreatedAt, which has whole seconds only
	Set tSpans = $SELECT($IsObject(tTrace): ..Rows("SELECT ID, SpanId, ParentSpanId, Name, StartTs, EndTs, DurationMs, Status, Attributes, Exported FROM AgenticProd_Data.Span WHERE TraceId = ? ORDER BY CASE WHEN ParentSpanId IS NULL THEN 0 ELSE 1 END, StartTs, ID", tTrace.TraceId), 1: [])
	Set tIter = tSpans.%GetIterator()
	While tIter.%GetNext(, .tSpan) {
		Set tAttrs = $SELECT(tSpan.Attributes '= "": ##class(%DynamicObject).%FromJSON(tSpan.Attributes), 1: {})
		Do tSpan.%Set("Attributes", tAttrs)
		Set:'$DATA(tByName(tSpan.Name)) tByName(tSpan.Name) = tAttrs
	}
	Set tSteps = []

	Set tClass = $SELECT($DATA(tByName("router check")): tByName("router check").%Get("agentic.error_class"), 1: "")
	Set:tClass="" tClass = tLog.ErrorClass
	Do tSteps.%Push({"step":"router", "title":"Router check",
		"text":("LabRouter checked the message and stopped it ("_tClass_"): "_$SELECT(tLog.ErrorText '= "": ..Mask(tLog.ErrorText, .tSecrets), 1: "no problem text recorded")_".")})

	Set tFlags = [], tDecision = $SELECT(tLog.DecisionJSON '= "": ##class(%DynamicObject).%FromJSON(tLog.DecisionJSON), 1: {})
	If $IsObject(tDecision.evidence) {
		Set tEv = tDecision.evidence.%GetIterator()
		While tEv.%GetNext(, .tLine) {
			Do:$EXTRACT(tLine, 1, 26)="suspicious instruction in " tFlags.%Push($PIECE($EXTRACT(tLine, 27, *), ": "))
		}
	}
	Do tSteps.%Push({"step":"injection", "title":"Injection check", "flagged":(tFlags),
		"text":($SELECT(tFlags.%Size(): "InjectionGuard found instruction-like text in "_..Join(tFlags)_". The agent still saw it, as marked data, but nothing it proposes for this message can be applied automatically.",
			1: "InjectionGuard found no instruction-like text in the free-text fields."))})

	Do tSteps.%Push(..AgentStep(tLog, .tSecrets))

	Set tGround = ..GroundingStep(tLog, .tSecrets)
	Do:$IsObject(tGround) tSteps.%Push(tGround)

	Set tTriage = $SELECT($DATA(tByName("triage decision")): tByName("triage decision").%Get("agentic.final_outcome"), 1: "")
	Do tSteps.%Push({"step":"triage", "title":"Triage rule", "outcome":(..TriageOutcome(tLog, tTriage)), "text":(..TriageText(tLog, ..TriageOutcome(tLog, tTriage), .tSecrets))})

	Do tSteps.%Push(..ReviewStep(tLog, ..TriageOutcome(tLog, tTriage), .tSecrets))

	Set tFHIR = ..FHIRStatus(tLog.SessionId, tNS)
	Do:tFHIR'="" tSteps.%Push({"step":"fhir", "title":"FHIR out", "text":("FHIR R4 bundle "_tFHIR_$SELECT(tFHIR = "valid": ", written to the simulated NPHIES FHIR endpoint.", 1: ", not sent; the issues went to Triage."))})

	Set tN = 0, tIter = tSteps.%GetIterator()
	While tIter.%GetNext(, .tStep) {
		Do tStep.%Set("n", $INCREMENT(tN))
	}
	Set tCase = $SELECT(tLog.EvalRunId '= "": "EV"_tLog.EvalRunId_"-"_tLog.CaseId, 1: "")
	Set tOut = {"id":(+pId), "headerId":(tLog.HeaderId), "sessionId":(tLog.SessionId), "namespace":(tNS), "traceUrl":(..TraceUrl(tNS)), "case":(tCase),
		"decision":(tLog.Decision), "outcome":(tLog.Outcome), "createdAt":(tLog.CreatedAt),
		"traceId":($SELECT($IsObject(tTrace): tTrace.TraceId, 1: "")), "steps":(tSteps), "spans":(tSpans), "message":(tMessage)}
	Do:tOut.message="" tOut.%Set("message", "", "null")
	Do:tLog.SessionId="" tOut.%Set("sessionId", "", "null")
	Quit tOut
}

/// Visual Trace URL up to SESSIONID= for a session in pNamespace (default this one).
ClassMethod TraceUrl(pNamespace As %String = "") As %String
{
	Quit $SYSTEM.CSP.GetDefaultApp($SELECT(pNamespace '= "": pNamespace, 1: $NAMESPACE))_"/EnsPortal.VisualTrace.zen?SESSIONID="
}

/// "valid" or "invalid (n issues)" for the latest NphiesFHIROut result in session pSessionId of
/// pNamespace, "" when the session has none (FHIR output off, or the message never got that far).
ClassMethod FHIRStatus(pSessionId As %Integer, pNamespace As %String = "") As %String
{
	Quit:pSessionId="" ""
	New $NAMESPACE
	Set:pNamespace'="" $NAMESPACE = pNamespace
	Set tRow = ..Rows("SELECT TOP 1 r.Valid, r.IssueCount FROM Ens.MessageHeader h JOIN AgenticProd_Msg.FHIRResult r ON r.ID = h.MessageBodyId"
		_" WHERE h.SessionId = ? AND h.MessageBodyClassName = 'AgenticProd.Msg.FHIRResult' ORDER BY h.ID DESC", pSessionId).%Get(0)
	Quit:'$IsObject(tRow) ""
	Quit $SELECT(tRow.Valid: "valid", 1: "invalid ("_tRow.IssueCount_" issue"_$SELECT(tRow.IssueCount = 1: "", 1: "s")_")")
}

/// The agent's step: what it proposed, or why it was not called, and its tool calls in order.
/// A replay ran no tools; the recorded session's calls are listed and marked recorded.
ClassMethod AgentStep(pLog As AgenticProd.Data.DecisionLog, ByRef pSecrets) As %DynamicObject [ Internal ]
{
	Set tStep = {"step":"agent", "title":"Agent", "tools":[]}
	Set tUsage = ..Rows("SELECT TOP 1 Model, Replay, Decision, Confidence, AgentSessionId, PromptTokens, CompletionTokens, CostUsd, ToolCalls, DecisionJSON FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND Namespace = ? ORDER BY ID DESC", pLog.HeaderId, pLog.Namespace).%Get(0)
	If '$IsObject(tUsage) || (tUsage.Decision = "") {
		Set tWhy = $SELECT(pLog.Reason [ "agent not called a second time": "this message was built by a Triage fix that failed again, so a second agent round could loop",
			pLog.Reason [ "Daily token budget": "the daily token budget was used up",
			pLog.Reason [ "agent gave no decision": "it gave no decision ("_$PIECE(..Mask(pLog.Reason, .pSecrets), "agent gave no decision: ", 2)_")",
			1: "no agent run is recorded for this message")
		Do tStep.%Set("text", "The agent was not used: "_tWhy_". Triage sent the message to a person instead.")
		Quit tStep
	}
	Set tProposal = $SELECT(tUsage.DecisionJSON '= "": ##class(%DynamicObject).%FromJSON(tUsage.DecisionJSON), 1: {})
	Set tWhat = tUsage.Decision
	If (tUsage.Decision = "MAP_CODE") && $IsObject(tProposal.mapping) {
		Set tWhat = tWhat_": map local code "_..Mask(tProposal.mapping."local_code", .pSecrets)_" to LOINC "_tProposal.mapping.loinc_$SELECT(tProposal.mapping.display '= "": " ("_tProposal.mapping.display_")", 1: "")
	} ElseIf $IsObject(tProposal.fix) && tProposal.fix.%Size() {
		Set tFixes = [], tIter = tProposal.fix.%GetIterator()
		While tIter.%GetNext(, .tFix) {
			Do tFixes.%Push(tFix.path_" '"_..Mask(tFix.from, .pSecrets)_"' to '"_..Mask(tFix.to, .pSecrets)_"'")
		}
		Set tWhat = tWhat_": change "_..Join(tFixes)
	}
	Set tHow = $SELECT(tUsage.Replay: "The agent run was replayed from a recorded session, with no LLM call and no tools run. It",
		1: "The agent called "_tUsage.Model_" ("_(+tUsage.PromptTokens + tUsage.CompletionTokens)_" tokens, $"_$FNUMBER(tUsage.CostUsd, "", 6)_") and")
	Do tStep.%Set("text", tHow_" proposed "_tWhat_$SELECT(tUsage.Confidence '= "": ", confidence "_$FNUMBER(tUsage.Confidence, "", 2), 1: "")_".")
	Do tStep.%Set("replay", +tUsage.Replay, "boolean")
	Quit:tUsage.AgentSessionId="" tStep
	Set tCalls = ..Rows("SELECT Tool, Status, DurationMs, ResultLength, ErrorText FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? ORDER BY ID", tUsage.AgentSessionId, pLog.Namespace)
	Set tIter = tCalls.%GetIterator()
	While tIter.%GetNext(, .tCall) {
		Set tResult = $CASE(tCall.Status, "OK": "returned "_+tCall.ResultLength_" characters", "DENIED": "refused by the read-only policy", : "failed")
		Set:(tCall.Status'="OK")&&(tCall.ErrorText'="") tResult = tResult_": "_$EXTRACT(..Mask(tCall.ErrorText, .pSecrets), 1, 120)
		Set tItem = {"tool":(tCall.Tool), "status":(tCall.Status), "durationMs":(tCall.DurationMs),
			"text":(tCall.Tool_" "_tResult_$SELECT(tCall.DurationMs '= "": " in "_tCall.DurationMs_" ms", 1: ""))}
		Do tItem.%Set("recorded", +tUsage.Replay, "boolean")
		Do tStep.tools.%Push(tItem)
	}
	// AI Hub's load_skill runs outside the audit policy, so it has no ToolCall row
	Set tUnaudited = tUsage.ToolCalls - tCalls.%Size()
	Do:tUnaudited>0 tStep.%Set("unauditedToolCalls", tUnaudited)
	Quit tStep
}

/// The grounding gate's checks on the agent's decision; "" when none ran (gate off, no agent run,
/// or a row from before the gate).
ClassMethod GroundingStep(pLog As AgenticProd.Data.DecisionLog, ByRef pSecrets) As %DynamicObject [ Internal ]
{
	Quit:pLog.GroundingJSON="" ""
	Set tGround = ##class(%DynamicObject).%FromJSON(pLog.GroundingJSON)
	Set tStep = {"step":"grounding", "title":"Grounding check", "checks":[]}
	Set tIter = tGround.checks.%GetIterator()
	While tIter.%GetNext(, .tCheck) {
		Set tItem = {"check":(tCheck.check), "text":(tCheck.check_": "_..Mask(tCheck.detail, .pSecrets))}
		Do tItem.%Set("pass", ''tCheck.pass, "boolean")
		Do tStep.checks.%Push(tItem)
	}
	If tGround.grounded {
		Do tStep.%Set("status", "passed")
		Do tStep.%Set("text", "Triage traced every claim in the proposal to the message, this run's tool results or the LOINC knowledge base ("_tStep.checks.%Size()_" checks).")
	} Else {
		Do tStep.%Set("status", $SELECT(tGround.strictness = "warn": "warned", 1: "caught"))
		Do tStep.%Set("text", "Some claims could not be traced ("_$TRANSLATE(tGround.failed, ",", " ")_"). "_$SELECT(tGround.strictness = "warn": "Grounding is in warn mode, so this was recorded and shown to the reviewer only.", 1: "Grounding is enforced, so the proposal was not acted on and went to a person."))
	}
	Quit tStep
}

/// What Triage itself decided before any review. pSpanOutcome is the "triage decision" span's
/// agentic.final_outcome; a review overwrites DecisionLog.Outcome, so without the span it is
/// worked out from the decision and its reason.
ClassMethod TriageOutcome(pLog As AgenticProd.Data.DecisionLog, pSpanOutcome As %String) As %String [ Internal ]
{
	Quit:pSpanOutcome'="" pSpanOutcome
	Quit:(pLog.Outcome'="APPROVED")&&($EXTRACT(pLog.Outcome, 1, 7)'="REVIEW_") pLog.Outcome
	Quit:$EXTRACT(pLog.Reason, 1, 16)="downgraded from " "DOWNGRADED:"_$PIECE($EXTRACT(pLog.Reason, 17, *), ":")
	Quit "SENT_FOR_APPROVAL"
}

ClassMethod TriageText(pLog As AgenticProd.Data.DecisionLog, pOutcome As %String, ByRef pSecrets) As %String [ Internal ]
{
	If $EXTRACT(pOutcome, 1, 9) = "OBSERVED:" {
		Set tWould = $EXTRACT(pOutcome, 10, *)
		Quit "Observe mode: Triage checked the proposal (result "_tWould_") and logged it, but sent, resent, rejected and asked nothing. The message is still where the production left it."
	}
	If $EXTRACT(pOutcome, 1, 9) = "PROPOSED:" {
		Quit "Propose mode: Triage would have done "_$EXTRACT(pOutcome, 10, *)_" on its own; it sent the proposal to a reviewer instead."
	}
	Set tAction = $PIECE(pOutcome, ":", 2)
	If $EXTRACT(pOutcome, 1, 11) = "DOWNGRADED:" {
		Set tWhy = $PIECE($PIECE($EXTRACT(pLog.Reason, 17, *), ": ", 2, *), " (agent: ")
		Quit "Triage did not accept "_tAction_": "_$SELECT(tWhy '= "": ..Mask(tWhy, .pSecrets), 1: "the action matrix does not allow it")_". It turned the proposal into ESCALATE and sent it to a person."
	}
	Quit:pOutcome="APPLIED" "Triage re-checked the fix itself (validation passed, confidence above the threshold, a whitelisted change, no patient identity fields) and sent a fixed copy on. The original message is unchanged."
	Quit:pOutcome="RESENT" "RESEND is allowed for a TRANSIENT error that was not resent before, so Triage resent the original message."
	Quit:pOutcome="REJECTED" "REJECT is allowed only for STRUCTURE_ERROR or ROUTING, which only the sender can fix, so Triage returned the message to the sender."
	If $EXTRACT(pOutcome, 1, 6) = "ERROR:" Quit "Triage chose "_tAction_" but could not send the result; the message is still failed."
	Quit:pLog.Decision="MAP_CODE" "A new code mapping is never applied automatically: Triage sent an approval task to a reviewer."
	Quit "The message needs a person: Triage sent an approval task to a reviewer."
}

/// The reviewer's answer, "waiting" when a task is open, or that no review was needed.
ClassMethod ReviewStep(pLog As AgenticProd.Data.DecisionLog, pTriageOutcome As %String, ByRef pSecrets) As %DynamicObject [ Internal ]
{
	Set tStep = {"step":"review", "title":"Reviewer"}
	Set tAsked = (pTriageOutcome = "SENT_FOR_APPROVAL") || ($EXTRACT(pTriageOutcome, 1, 11) = "DOWNGRADED:") || ($EXTRACT(pTriageOutcome, 1, 9) = "PROPOSED:")
	If pLog.ReviewedAt = "" {
		Do tStep.%Set("status", $SELECT(tAsked: "waiting", 1: "none"))
		Do tStep.%Set("text", $SELECT(tAsked: "Waiting for a reviewer in the Workflow inbox.", 1: "No review needed."))
		Quit tStep
	}
	If pLog.Reviewer = "eval" {
		Do tStep.%Set("status", "closed")
		Do tStep.%Set("text", "Closed by the eval runner at "_pLog.ReviewedAt_" (UTC); not reviewed by a person.")
		Quit tStep
	}
	Set tWhat = $CASE(pLog.Outcome,
		"APPROVED": "approved the mapping "_..Mask(pLog.LocalCode, .pSecrets)_" to LOINC "_pLog.Loinc_"; it was added to the lookup table and the original message was resent",
		"REVIEW_APPLIED": "approved the fix; Triage re-validated it and sent a fixed copy on",
		"REVIEW_CLOSED": "approved and closed the task; nothing was changed",
		"REVIEW_REJECTED": "rejected the proposal; nothing was changed",
		"REVIEW_RESENT": "approved the resend; the message was sent again to its own target",
		"REVIEW_RETURNED": "approved returning the message to the sender",
		"REVIEW_BAD_LOINC": "approved a LOINC that was not accepted, so nothing was written",
		"REVIEW_FIX_FAILED": "approved the fix, but it failed the re-check, so nothing was sent",
		: "answered the task (outcome "_pLog.Outcome_")")
	Do tStep.%Set("status", $SELECT(pLog.Outcome = "REVIEW_REJECTED": "rejected", 1: "approved"))
	Do tStep.%Set("text", $SELECT(pLog.Reviewer '= "": "Reviewer "_pLog.Reviewer, 1: "A reviewer")_" "_tWhat_" at "_pLog.ReviewedAt_" (UTC)."_$SELECT(pLog.ReviewNote '= "": " Note: "_..Mask(pLog.ReviewNote, .pSecrets), 1: ""))
	Quit tStep
}

/// Masked text of the message body (the masking get_failed_message uses); "" when the body
/// was purged or its class has no masking rule. pSecrets(value) = the values that masking hides,
/// for Mask. pNamespace: where the header lives (default this namespace).
ClassMethod MaskedMessage(pHeaderId As %Integer, Output pSecrets, pNamespace As %String = "") As %String [ Internal ]
{
	Kill pSecrets
	Set tText = ""
	New $NAMESPACE
	Try {
		Set:pNamespace'="" $NAMESPACE = pNamespace
		Quit:$$$ISERR(##class(AgenticProd.Tools.Base).OpenBody(pHeaderId, .tBody))
		Set tMasker = ##class(AgenticProd.Tools.Base).MaskerFor($CLASSNAME(tBody))
		Quit:tMasker=""
		Quit:$$$ISERR($CLASSMETHOD(tMasker, "MaskedText", tBody, .tText))
		If tBody.%Extends("EnsLib.HL7.Message") {
			Set tMasked = ##class(AgenticProd.Tools.HL7).#MASKEDPID, tSeps = tBody.Separators
			Set tRaw = $REPLACE($REPLACE(tBody.OutputToString(), $CHAR(13,10), $CHAR(13)), $CHAR(10), $CHAR(13))
			For i = 1:1:$LENGTH(tRaw, $CHAR(13)) {
				Set tLine = $PIECE(tRaw, $CHAR(13), i)
				Continue:$PIECE(tLine, $EXTRACT(tSeps))'="PID"
				For f = 1:1:$LENGTH(tMasked, ",") {
					Set tField = $PIECE(tMasked, ",", f)
					Continue:tField=""
					Set tValue = $PIECE(tLine, $EXTRACT(tSeps), tField + 1)
					Do ..AddSecret(tValue, $EXTRACT(tSeps, 2, 3)_$EXTRACT(tSeps, 5), .pSecrets)
				}
			}
		}
	} Catch ex {
		Set tText = ""
	}
	Quit tText
}

/// pValue and each of its components, repeats and subcomponents (pSeps = component, repetition
/// and subcomponent separators) as secrets. Pieces shorter than 3 characters would mask
/// ordinary text, so they are left out.
ClassMethod AddSecret(pValue As %String, pSeps As %String, ByRef pSecrets) [ Internal ]
{
	Quit:$LENGTH(pValue)<3
	Set pSecrets(pValue) = ""
	For s = 1:1:$LENGTH(pSeps) {
		Set tSep = $EXTRACT(pSeps, s)
		Continue:pValue'[tSep
		For p = 1:1:$LENGTH(pValue, tSep) Do ..AddSecret($PIECE(pValue, tSep, p), pSeps, .pSecrets)
	}
}

/// pText with every pSecrets value replaced by ***, longest first so a full name goes before its parts.
ClassMethod Mask(pText As %String, ByRef pSecrets) As %String
{
	Quit:pText="" ""
	Set tKey = ""
	For {
		Set tKey = $ORDER(pSecrets(tKey))
		Quit:tKey=""
		Set tByLen(-$LENGTH(tKey), tKey) = ""
	}
	Set tLen = ""
	For {
		Set tLen = $ORDER(tByLen(tLen))
		Quit:tLen=""
		Set tKey = ""
		For {
			Set tKey = $ORDER(tByLen(tLen, tKey))
			Quit:tKey=""
			Set pText = $REPLACE(pText, tKey, "***")
		}
	}
	Quit pText
}

ClassMethod Join(pList As %DynamicArray) As %String [ Internal ]
{
	Set tOut = "", tIter = pList.%GetIterator()
	While tIter.%GetNext(, .tItem) {
		Set tOut = tOut_$SELECT(tOut '= "": ", ", 1: "")_tItem
	}
	Quit tOut
}

/// Agent metrics for the dashboard charts; live traffic only unless pIncludeEval. Replays are
/// left out of tokens and latency (they repeat a recorded run). Times are UTC.
/// tokens: per model, split so the parts add up to the total (input = prompt minus cache reads,
/// output = completion minus reasoning). latency, approval wait and steps: nearest-rank p50/p95.
ClassMethod MetricsData(pIncludeEval As %Boolean = 0) As %DynamicObject
{
	Set tUsageWhere = "(Replay = 0 OR Replay IS NULL)"_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL")
	Set tOut = {"includeEval":(''pIncludeEval), "generatedAt":($ZDATETIME($ZTIMESTAMP, 3))}
	Do tOut.%Set("includeEval", ''pIncludeEval, "boolean")

	Set tOut.tokens = ..Rows("SELECT %EXACT(Model) AS Model, COUNT(*) AS Runs, SUM(PromptTokens) - SUM(CacheReadTokens) AS InputTokens, SUM(CacheReadTokens) AS CachedInputTokens,"
		_" SUM(CompletionTokens) - SUM(ReasoningTokens) AS OutputTokens, SUM(ReasoningTokens) AS ReasoningTokens, SUM(CostUsd) AS CostUsd"
		_" FROM AgenticProd_Data.Usage WHERE "_tUsageWhere_" AND Model IS NOT NULL GROUP BY %EXACT(Model) ORDER BY Model")

	Set tOut.latency = ..Quantiles("SELECT Model AS K, TotalMs / 1000 AS V FROM AgenticProd_Data.Usage WHERE "_tUsageWhere_" AND TotalMs IS NOT NULL AND Model IS NOT NULL", "model")

	// ToolCall has no EvalRunId: a call is eval traffic when its session's Usage row is
	Set tToolWhere = $SELECT(pIncludeEval: "", 1: " AND AgentSessionId IN (SELECT AgentSessionId FROM AgenticProd_Data.Usage WHERE EvalRunId IS NULL)")
	Set tOut.tools = ..Rows("SELECT %EXACT(Tool) AS Tool, COUNT(*) AS Calls, ROUND(AVG(DurationMs), 1) AS AvgMs,"
		_" SUM(CASE WHEN Status = 'OK' THEN 1 ELSE 0 END) AS Ok, SUM(CASE WHEN Status = 'ERROR' THEN 1 ELSE 0 END) AS Errors,"
		_" SUM(CASE WHEN Status = 'DENIED' THEN 1 ELSE 0 END) AS Denied"
		_" FROM AgenticProd_Data.ToolCall WHERE 1 = 1"_tToolWhere_" GROUP BY %EXACT(Tool) ORDER BY Calls DESC")
	Set tOut.validateFix = ..Rows("SELECT ISNULL(Verdict, 'NOT_RECORDED') AS Verdict, COUNT(*) AS Calls FROM AgenticProd_Data.ToolCall"
		_" WHERE Tool = 'validate_fix' AND Status = 'OK'"_tToolWhere_" GROUP BY ISNULL(Verdict, 'NOT_RECORDED') ORDER BY Calls DESC")

	Set tOut.decisionMix = ..DecisionMix(pIncludeEval)
	Set tOut.outcomes = {"applied":0, "approval":0, "rejected":0, "resent":0, "other":0}
	Set tOut.agentVsFinal = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT d.Outcome, (SELECT MAX(u.Decision) FROM AgenticProd_Data.Usage u WHERE u.HeaderId = d.HeaderId AND u.Namespace = d.Namespace) AS AgentDecision"
		_" FROM AgenticProd_Data.DecisionLog d"_$SELECT(pIncludeEval: "", 1: " WHERE d.EvalRunId IS NULL"))
	While tRS.%Next() {
		Set tGroup = ..OutcomeGroup(tRS.Outcome)
		Do tOut.outcomes.%Set(tGroup, tOut.outcomes.%Get(tGroup) + 1)
		// No Usage row: the logged ESCALATE was Triage's own (loop guard, budget, no checker)
		Set tAgent = $SELECT(tRS.AgentDecision '= "": tRS.AgentDecision, 1: "no agent run")
		Set tPair(tAgent, tGroup) = $GET(tPair(tAgent, tGroup)) + 1
	}
	Set tAgent = ""
	For {
		Set tAgent = $ORDER(tPair(tAgent))
		Quit:tAgent=""
		Set tRow = {"agent":(tAgent)}
		For tGroup = "applied", "approval", "rejected", "resent", "other" Do tRow.%Set(tGroup, +$GET(tPair(tAgent, tGroup)))
		Do tOut.agentVsFinal.%Push(tRow)
	}

	Set tLogWhere = $SELECT(pIncludeEval: "", 1: " AND d.EvalRunId IS NULL")
	// Eval tasks are closed by Eval.Runner, not answered: their wait time is not a person's
	Set tApproval = ..Quantiles("SELECT 'all' AS K, DATEDIFF('s', d.CreatedAt, d.ReviewedAt) AS V FROM AgenticProd_Data.DecisionLog d"
		_" WHERE d.ReviewedAt IS NOT NULL AND (d.Reviewer IS NULL OR d.Reviewer <> 'eval')"_tLogWhere, "key").%Get(0)
	// Tasks are messages in this namespace, so only this namespace's log rows can match them
	Set tWaiting = ..Rows("SELECT COUNT(*) AS N, MIN(d.CreatedAt) AS Oldest FROM EnsLib_Workflow.TaskResponse r"
		_" JOIN AgenticProd_Msg.ApprovalTask t ON t.ID = r.TaskStatus_Request JOIN AgenticProd_Data.DecisionLog d ON d.HeaderId = t.HeaderId AND d.Namespace = ?"
		_" WHERE r.TaskStatus_IsComplete = 0"_tLogWhere, $NAMESPACE).%Get(0)
	Set tOut.approval = {"answered":0, "p50Seconds":null, "p95Seconds":null, "waiting":(+tWaiting.N), "oldestWaitingSeconds":null}
	If $IsObject(tApproval) Set tOut.approval.answered = tApproval.count, tOut.approval.p50Seconds = tApproval.p50, tOut.approval.p95Seconds = tApproval.p95
	Do:tWaiting.Oldest'="" tOut.approval.%Set("oldestWaitingSeconds", ##class(AgenticProd.Telemetry.Trace).ZtsDiff($ZTIMESTAMP, $ZDATETIMEH(tWaiting.Oldest, 3)) \ 1)

	// What one agent MAP_CODE run costs on average; a learned mapping saves one run per message
	Set tSaved = ..Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall"_$SELECT(pIncludeEval: "", 1: " WHERE EvalRunId IS NULL")).%Get(0)
	Set tRun = ..Rows("SELECT COUNT(*) AS Runs, AVG(PromptTokens + CompletionTokens) AS Tokens, AVG(CostUsd) AS Cost FROM AgenticProd_Data.Usage WHERE Decision = 'MAP_CODE' AND (Replay = 0 OR Replay IS NULL)").%Get(0)
	Set tOut.saved = {"calls":(+tSaved.N), "basedOnRuns":(+tRun.Runs), "tokens":null, "costUsd":null}
	If tRun.Runs Set tOut.saved.tokens = tSaved.N * tRun.Tokens \ 1, tOut.saved.costUsd = $NORMALIZE(tSaved.N * tRun.Cost, 6)
	Set tOut.learnedMappings = +..Rows("SELECT COUNT(DISTINCT LocalCode) AS N FROM AgenticProd_Data.DecisionLog d WHERE d.Outcome = 'APPROVED'"_tLogWhere).%Get(0).N
	Set tOut.unsafeBlocked = +..Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog d WHERE d.Outcome %STARTSWITH 'DOWNGRADED:'"_tLogWhere).%Get(0).N

	Set tOut.steps = ..Quantiles("SELECT Name AS K, DurationMs AS V FROM AgenticProd_Data.Span WHERE Name IN ('router check', 'agent run', 'triage decision') AND DurationMs IS NOT NULL"
		_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL"), "step")
	Quit tOut
}

/// [{<pKeyName>, count, p50, p95}] over rows K, V of pSQL, in K order.
ClassMethod Quantiles(pSQL As %String, pKeyName As %String) As %DynamicArray [ Internal ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, pSQL)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	While tRS.%Next() {
		Set tK = tRS.K, tV = tRS.V
		Continue:(tK="")||(tV="")
		Set tN(tK) = $GET(tN(tK)) + 1, tSorted(tK, +tV, tN(tK)) = ""
	}
	Set tOut = [], tK = ""
	For {
		Set tK = $ORDER(tN(tK))
		Quit:tK=""
		Kill tOne
		Merge tOne = tSorted(tK)
		Set tRow = {}
		Do tRow.%Set(pKeyName, tK), tRow.%Set("count", tN(tK))
		Do tRow.%Set("p50", $NORMALIZE(##class(AgenticProd.Eval.Runner).Percentile(.tOne, tN(tK), .5), 3), "number")
		Do tRow.%Set("p95", $NORMALIZE(##class(AgenticProd.Eval.Runner).Percentile(.tOne, tN(tK), .95), 3), "number")
		Do tOut.%Push(tRow)
	}
	Quit tOut
}

/// Decisions per UTC hour for the last 24 hours, by what finally happened:
/// {hours:["HH:00",...], applied:[], approval:[], rejected:[], resent:[], other:[]}.
ClassMethod DecisionMix(pIncludeEval As %Boolean) As %DynamicObject [ Internal ]
{
	Set tNow = $ZTIMESTAMP, tHourNow = (+tNow * 24) + ($PIECE(tNow, ",", 2) \ 3600)
	Set tFrom = tHourNow - 23
	Set tSince = $ZDATETIME((tFrom \ 24)_","_((tFrom # 24) * 3600), 3)
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Outcome, CreatedAt FROM AgenticProd_Data.DecisionLog WHERE CreatedAt >= ?"_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL"), tSince)
	While tRS.%Next() {
		Set tAt = $ZDATETIMEH(tRS.CreatedAt, 3), tHour = (+tAt * 24) + ($PIECE(tAt, ",", 2) \ 3600) - tFrom
		Continue:(tHour<0)||(tHour>23)
		Set tCat = ..OutcomeGroup(tRS.Outcome), tCount(tCat, tHour) = $GET(tCount(tCat, tHour)) + 1
	}
	Set tOut = {"hours":[]}
	For tCat = "applied", "approval", "rejected", "resent", "other" Do tOut.%Set(tCat, [])
	For h = 0:1:23 {
		Do tOut.hours.%Push($TRANSLATE($JUSTIFY((tFrom + h) # 24, 2), " ", "0")_":00")
		For tCat = "applied", "approval", "rejected", "resent", "other" Do tOut.%Get(tCat).%Push(+$GET(tCount(tCat, h)))
	}
	Quit tOut
}

/// Dashboard colour group of a DecisionLog Outcome: applied, approval (sent to a person,
/// whatever the review did), rejected, resent or other (errors).
ClassMethod OutcomeGroup(pOutcome As %String) As %String
{
	Quit:pOutcome="APPLIED" "applied"
	Quit:pOutcome="REJECTED" "rejected"
	Quit:pOutcome="RESENT" "resent"
	Quit:(pOutcome="SENT_FOR_APPROVAL")||(pOutcome="APPROVED")||($EXTRACT(pOutcome, 1, 11)="DOWNGRADED:")||($EXTRACT(pOutcome, 1, 7)="REVIEW_")||($EXTRACT(pOutcome, 1, 9)="PROPOSED:") "approval"
	Quit "other"
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

/// Eval runs, newest first. A RUNNING run with no result for STALESECONDS shows as STOPPED: a run
/// whose job died (container restart, terminal closed) never gets to set DONE or ERROR itself.
/// headline is true on the newest finished live run over all cases, the one the README quotes.
ClassMethod EvalRunsData() As %DynamicArray
{
	Set tRows = ..Rows("SELECT r.ID, r.Label, r.Model, r.Mode, r.Cases, r.Status, r.StartedAt, r.CaseCount, r.Accuracy, r.ExactAccuracy, r.MappingAccuracy,"
		_" r.UnsafeAgent, r.UnsafeFinal, r.TimedOut, r.CostPerMessageUsd, r.P95Seconds,"
		_" (SELECT MAX(e.CreatedAt) FROM AgenticProd_Data.EvalResult e WHERE e.RunId = r.ID) AS LastResultAt"
		_" FROM AgenticProd_Data.EvalRun r ORDER BY r.ID DESC")
	Set tIter = tRows.%GetIterator(), tHeadSeen = 0
	While tIter.%GetNext(, .tRow) {
		If tRow.Status = "RUNNING" {
			Set tLast = $SELECT(tRow.LastResultAt '= "": tRow.LastResultAt, 1: tRow.StartedAt)
			Set:(##class(AgenticProd.Telemetry.Trace).ZtsDiff($ZTIMESTAMP, $ZDATETIMEH(tLast, 3)) > ..#STALESECONDS) tRow.Status = "STOPPED"
		}
		Do tRow.%Remove("LastResultAt")
		Set tHead = 'tHeadSeen && (tRow.Mode = "live") && (tRow.Cases = "all") && (tRow.Status = "DONE")
		Set:tHead tHeadSeen = 1
		Do tRow.%Set("headline", tHead, "boolean")
	}
	Quit tRows
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
