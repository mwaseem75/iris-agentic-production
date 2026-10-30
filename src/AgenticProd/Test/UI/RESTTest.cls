/// UI.REST data builders on stub rows, and the /agenticprod web app over HTTP. No LLM.
/// The HTTP tests need Setup.DashboardSetup to have run (web app, reviewer in the dashboard role).
Class AgenticProd.Test.UI.RESTTest Extends AgenticProd.Test.Case
{

/// Fake run ID for stub DecisionLog, EvalRun and EvalResult rows.
Parameter RUNID = 999903;

Method TestSummaryCountsOutcomes()
{
	Set tBefore = ##class(AgenticProd.UI.REST).SummaryData(1)
	Set tLiveBefore = ##class(AgenticProd.UI.REST).SummaryData(0)
	Do $$$AssertStatusOK(..AddLogRow(-9301, "AUTO_FIX", "APPLIED"))
	Do $$$AssertStatusOK(..AddLogRow(-9302, "MAP_CODE", "SENT_FOR_APPROVAL"))
	Do $$$AssertStatusOK(..AddLogRow(-9303, "ESCALATE", "DOWNGRADED:AUTO_FIX"))
	Do $$$AssertStatusOK(..AddLogRow(-9304, "MAP_CODE", "APPROVED"))
	Do $$$AssertStatusOK(..AddLogRow(-9305, "REJECT", "REJECTED"))
	Set tAfter = ##class(AgenticProd.UI.REST).SummaryData(1)
	Set tLiveAfter = ##class(AgenticProd.UI.REST).SummaryData(0)
	Do $$$AssertEquals(tLiveAfter.triaged, tLiveBefore.triaged, "eval rows stay out of the live KPIs")
	Do $$$AssertEquals(tLiveAfter.includeEval, 0)
	Do $$$AssertEquals(tAfter.changedByTriage - tBefore.changedByTriage, 1, "the DOWNGRADED row")
	Do $$$AssertEquals(tAfter.triaged - tBefore.triaged, 5)
	Do $$$AssertEquals(tAfter.autoFixed - tBefore.autoFixed, 1)
	Do $$$AssertEquals(tAfter.sentForApproval - tBefore.sentForApproval, 3, "pending, downgraded and approved all went to a person")
	Do $$$AssertEquals(tAfter.waiting - tBefore.waiting, 2, "approved is no longer waiting")
	Do $$$AssertEquals(tAfter.rejected - tBefore.rejected, 1)
	Do $$$AssertEquals(tAfter.mappingsLearned - tBefore.mappingsLearned, 1)
	Do $$$AssertEquals(tAfter.tokensToday, ##class(AgenticProd.Operation.Agent).TokensUsedToday(), "same count the budget uses")
	Do $$$AssertTrue(tAfter.dailyTokenBudget > 0, "budget from the agent item: "_tAfter.dailyTokenBudget)
	Do $$$AssertEquals(tAfter.tokensPercent, $NORMALIZE(tAfter.tokensToday / tAfter.dailyTokenBudget * 100, 0))
	Do $$$AssertEquals(tAfter.overBudget, tAfter.tokensToday >= tAfter.dailyTokenBudget)
	Do $$$AssertTrue(tAfter.traceUrl [ "EnsPortal.VisualTrace.zen?SESSIONID=", tAfter.traceUrl)
	Do $$$AssertTrue(tAfter.productionUrl [ "EnsPortal.ProductionConfig.zen?PRODUCTION=AgenticProd.Production", tAfter.productionUrl)
	Do $$$AssertTrue(tAfter.inboxUrl [ "_DeepSee.UserPortal.Workflow.zen", tAfter.inboxUrl)
}

/// Cost per message is for the agent item's current model only, live runs only.
Method TestCostPerMessageCurrentModel()
{
	Set tBefore = ##class(AgenticProd.UI.REST).SummaryData(0)
	Set tAllBefore = ##class(AgenticProd.UI.REST).SummaryData(1)
	Do $$$AssertTrue(tBefore.model '= "", "model named: "_tBefore.model)
	Do $$$AssertStatusOK(..AddUsageRow(-9331, "MAP_CODE", tBefore.model, 0, ""))
	Do $$$AssertStatusOK(..AddUsageRow(-9332, "MAP_CODE", "some-other-model", 0, ""))
	Do $$$AssertStatusOK(..AddUsageRow(-9333, "MAP_CODE", tBefore.model, 1, ""))
	Do $$$AssertStatusOK(..AddUsageRow(-9334, "MAP_CODE", tBefore.model, 0, ..#RUNID))
	Set tAfter = ##class(AgenticProd.UI.REST).SummaryData(0)
	Do $$$AssertEquals(tAfter.agentRunsModel - tBefore.agentRunsModel, 1, "other model, replay and eval rows left out")
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).SummaryData(1).agentRunsModel - tAllBefore.agentRunsModel, 2, "eval row counted with eval included")
}

/// Live rows: Triage changes, InjectionGuard flags and the reason when no agent ran.
Method TestDecisionTags()
{
	Set tChangedBefore = ##class(AgenticProd.UI.REST).SummaryData(0).changedByTriage
	Set tFlagged = {"decision":"ESCALATE","evidence":["fix reformats OBX-14","suspicious instruction in OBX(1):5: ignore previous"]}
	Do $$$AssertStatusOK(..AddLogRow(-9321, "ESCALATE", "DOWNGRADED:AUTO_FIX", "", tFlagged.%ToJSON(), "downgraded from AUTO_FIX"))
	Do $$$AssertStatusOK(..AddUsageRow(-9321, "AUTO_FIX", "test", 0, ""))
	Do $$$AssertStatusOK(..AddLogRow(-9322, "ESCALATE", "SENT_FOR_APPROVAL", "", "", "message built by a Triage AUTO_FIX failed again; agent not called a second time"))
	Do $$$AssertStatusOK(..AddLogRow(-9323, "ESCALATE", "SENT_FOR_APPROVAL", "", "", "Daily token budget used up (10 of 1 tokens); agent not called"))
	Do $$$AssertStatusOK(..AddLogRow(-9324, "MAP_CODE", "SENT_FOR_APPROVAL", "", "", "replayed"))
	Do $$$AssertStatusOK(..AddUsageRow(-9324, "MAP_CODE", "test", 1, ""))
	Do $$$AssertStatusOK(..AddLogRow(-9325, "ESCALATE", "SENT_FOR_APPROVAL", "", "", "over the per-message limit"))
	Do $$$AssertStatusOK(..AddUsageRow(-9325, "MAP_CODE", "test", 0, ""))
	Do $$$AssertStatusOK(..AddLogRow(-9326, "AUTO_FIX", "APPLIED"))
	Set tRows = ##class(AgenticProd.UI.REST).DecisionsData(6, 0)
	For i = 0:1:tRows.%Size() - 1 Set tRow = tRows.%Get(i), tBy(tRow.HeaderId) = tRow
	Do $$$AssertTrue('$DATA(tBy(-9326)), "eval row left out of live decisions")
	Do $$$AssertEquals(tBy(-9321).triageChanged, 1)
	Do $$$AssertEquals(tBy(-9321).AgentDecision, "AUTO_FIX")
	Do $$$AssertEquals(tBy(-9321).flagged.%ToJSON(), "[""OBX(1):5""]")
	Do $$$AssertEquals(tBy(-9321).agentCalled, 1)
	Do $$$AssertEquals(tBy(-9321).%IsDefined("DecisionJSON"), 0, "raw JSON not sent")
	Do $$$AssertEquals(tBy(-9322).agentCalled, 0)
	Do $$$AssertEquals(tBy(-9322).noAgentReason, "loop guard")
	Do $$$AssertEquals(tBy(-9322).triageChanged, 0)
	Do $$$AssertEquals(tBy(-9323).noAgentReason, "budget")
	Do $$$AssertEquals(tBy(-9324).noAgentReason, "replay")
	Do $$$AssertEquals(tBy(-9325).triageChanged, 1, "ESCALATE over an agent MAP_CODE")
	Do $$$AssertEquals(tBy(-9325).flagged.%Size(), 0)
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).SummaryData(0).changedByTriage - tChangedBefore, 2)
	Set tAll = ##class(AgenticProd.UI.REST).DecisionsData(7, 1)
	Do $$$AssertEquals(tAll.%Get(0).HeaderId, -9326, "eval row back with eval included")
}

Method TestDecisionsNewestFirstAndClamped()
{
	Do $$$AssertStatusOK(..AddLogRow(-9311, "AUTO_FIX", "APPLIED"))
	Do $$$AssertStatusOK(..AddLogRow(-9312, "REJECT", "REJECTED"))
	Set tRows = ##class(AgenticProd.UI.REST).DecisionsData(2, 1)
	Do $$$AssertEquals(tRows.%Size(), 2)
	Do $$$AssertEquals(tRows.%Get(0).HeaderId, -9312, "newest first")
	Do $$$AssertEquals(tRows.%Get(0).EvalRunId, ..#RUNID)
	Do $$$AssertEquals(tRows.%GetTypeOf(0), "object")
	Do $$$AssertEquals(tRows.%Get(0).%GetTypeOf("Confidence"), "number")
	Do $$$AssertEquals(tRows.%Get(0).%GetTypeOf("SessionId"), "null", "stub row has no session")
	Set tMax = ##class(AgenticProd.UI.REST).#MAXLIMIT
	Do $$$AssertTrue(##class(AgenticProd.UI.REST).DecisionsData(99999).%Size() <= tMax, "limit capped at "_tMax)
	// Include eval rows: the stub rows are eval rows, and a fresh install has no live traffic
	Do $$$AssertTrue(##class(AgenticProd.UI.REST).DecisionsData("x", 1).%Size() > 0, "bad limit falls back to the default")
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

/// A RUNNING run whose job died shows as STOPPED once STALESECONDS pass without a result.
Method TestStaleRunShowsStopped()
{
	For tAge = 60, 1200 {
		Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
		Set tRun.Label = "stale test", tRun.Model = "test", tRun.Mode = "replay", tRun.Status = "RUNNING"
		Set tRun.StartedAt = $ZDATETIME($ZDATETIMEH($ZDATETIME($ZTIMESTAMP, -2) - tAge, -2), 3)
		Do $$$AssertStatusOK(tRun.%Save())
		Set tId(tAge) = tRun.%Id()
	}
	Set tIter = ##class(AgenticProd.UI.REST).EvalRunsData().%GetIterator()
	While tIter.%GetNext(, .tR) {
		Set:tR.ID=tId(60) tFresh = tR.Status
		Set:tR.ID=tId(1200) tStale = tR.Status
	}
	Do $$$AssertEquals($GET(tFresh), "RUNNING")
	Do $$$AssertEquals($GET(tStale), "STOPPED")
	Set tHeadlines = 0, tIter = ##class(AgenticProd.UI.REST).EvalRunsData().%GetIterator()
	While tIter.%GetNext(, .tR) {
		Continue:'tR.headline
		Set tHeadlines = tHeadlines + 1
		Do $$$AssertTrue((tR.Mode = "live") && (tR.Cases = "all") && (tR.Status = "DONE"), "headline run "_tR.ID)
	}
	Do $$$AssertTrue(tHeadlines <= 1, "at most one headline")
	For tAge = 60, 1200 Do ##class(AgenticProd.Data.EvalRun).%DeleteId(tId(tAge))
}

/// Reviewer gets JSON and the page; no login and a wrong password get 401; the entry page
/// shows the IRIS login form to an anonymous browser.
/// Story of an approved mapping: steps in order, tool calls in order with short results, the Triage
/// rule from the span (the review overwrote DecisionLog.Outcome), the reviewer, and the trace.
Method TestStoryApprovedMapping()
{
	Set tHeader = -9341, tSession = "test-story-9341"
	Set tJSON = {"decision":"MAP_CODE","evidence":["suspicious instruction in NTE(1):3: ignore previous"]}.%ToJSON()
	Do $$$AssertStatusOK(..AddLogRow(tHeader, "MAP_CODE", "APPROVED", "", tJSON, "local GLU1 is glucose", .tLogId))
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(tLogId)
	Set tLog.ErrorText = "OBX(1):3 local code GLU1 not in LabCodeMap", tLog.ErrorClass = "UNMAPPED_CODE"
	Set tLog.LocalCode = "GLU1", tLog.Loinc = "2345-7", tLog.Reviewer = "reviewer", tLog.ReviewedAt = "2026-10-26 10:00:00"
	Do $$$AssertStatusOK(tLog.%Save())
	Set tUsage = ##class(AgenticProd.Data.Usage).%New()
	Set tUsage.HeaderId = tHeader, tUsage.AgentSessionId = tSession, tUsage.Model = "gpt-4o-mini", tUsage.Decision = "MAP_CODE"
	Set tUsage.Confidence = .9, tUsage.PromptTokens = 1000, tUsage.CompletionTokens = 100, tUsage.CostUsd = .0002, tUsage.ToolCalls = 3
	Set tUsage.DecisionJSON = {"decision":"MAP_CODE","mapping":{"local_code":"GLU1","loinc":"2345-7","display":"Glucose"}}.%ToJSON()
	Do $$$AssertStatusOK(tUsage.%Save())
	Do $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("get_failed_message", {}, "OK", 40, 812, "", tHeader, tSession))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("search_loinc", {}, "OK", 90, 300, "", tHeader, tSession))
	Set tTrace = "0123456789abcdef0123456789abcdef", tStart = ##class(AgenticProd.Telemetry.Trace).ZtsBefore(5000)
	Do $$$AssertStatusOK(##class(AgenticProd.Data.Span).Log(tTrace, "00000000000000a1", "", "triage hdr", tStart, $ZTIMESTAMP, "Ok", {}, tHeader))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.Span).Log(tTrace, "00000000000000a2", "00000000000000a1", "triage decision", ##class(AgenticProd.Telemetry.Trace).ZtsBefore(100), $ZTIMESTAMP, "Ok", {"agentic.final_outcome":"SENT_FOR_APPROVAL"}, tHeader))

	Set tStory = ##class(AgenticProd.UI.REST).StoryData(tLogId)
	Do $$$AssertTrue($IsObject(tStory), "story built")
	Quit:'$IsObject(tStory)
	Do $$$AssertEquals(tStory.traceId, tTrace)
	Do $$$AssertEquals(tStory.spans.%Size(), 2)
	Do $$$AssertEquals(tStory.spans.%Get(0).Name, "triage hdr", "spans by start time")
	Do $$$AssertEquals(tStory.spans.%Get(1).Attributes."agentic.final_outcome", "SENT_FOR_APPROVAL", "attributes sent as an object")
	Set tSteps = tStory.steps
	Do $$$AssertEquals(tSteps.%Size(), 5)
	For i = 0:1:tSteps.%Size() - 1 Set tStep(tSteps.%Get(i).step) = tSteps.%Get(i), tOrder = $GET(tOrder)_tSteps.%Get(i).step_","
	Do $$$AssertEquals(tOrder, "router,injection,agent,triage,review,")
	Do $$$AssertEquals(tSteps.%Get(4).n, 5, "steps numbered")
	Do $$$AssertTrue(tStep("router").text [ "GLU1 not in LabCodeMap", tStep("router").text)
	Do $$$AssertEquals(tStep("injection").flagged.%ToJSON(), "[""NTE(1):3""]")
	Do $$$AssertTrue(tStep("agent").text [ "map local code GLU1 to LOINC 2345-7", tStep("agent").text)
	Do $$$AssertEquals(tStep("agent").tools.%Size(), 2)
	Do $$$AssertEquals(tStep("agent").tools.%Get(0).tool, "get_failed_message", "tool calls in order")
	Do $$$AssertTrue(tStep("agent").tools.%Get(1).text [ "returned 300 characters in 90 ms", tStep("agent").tools.%Get(1).text)
	Do $$$AssertEquals(tStep("agent").unauditedToolCalls, 1, "load_skill")
	Do $$$AssertEquals(tStep("triage").outcome, "SENT_FOR_APPROVAL", "Triage's own outcome from the span")
	Do $$$AssertTrue(tStep("triage").text [ "never applied automatically", tStep("triage").text)
	Do $$$AssertEquals(tStep("review").status, "approved")
	Do $$$AssertTrue(tStep("review").text [ "reviewer approved the mapping GLU1 to LOINC 2345-7", tStep("review").text)
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).StoryData("x"), "", "bad ID")
	Do $$$AssertEquals(##class(AgenticProd.UI.REST).StoryData(999999999), "", "no such row")
}

/// No agent run, no trace, downgrade worked out from the reason, review still open.
Method TestStoryWaitingNoAgent()
{
	Do $$$AssertStatusOK(..AddLogRow(-9342, "ESCALATE", "DOWNGRADED:AUTO_FIX", "", "", "downgraded from AUTO_FIX: fix changes PID-7 (agent: date)", .tLogId))
	Set tStory = ##class(AgenticProd.UI.REST).StoryData(tLogId)
	Do $$$AssertEquals(tStory.spans.%Size(), 0)
	Do $$$AssertEquals(tStory.traceId, "")
	Do $$$AssertEquals(tStory.message, "", "stub header has no body")
	Do $$$AssertTrue(tStory.steps.%Get(2).text [ "not used", tStory.steps.%Get(2).text)
	Do $$$AssertEquals(tStory.steps.%Get(3).outcome, "DOWNGRADED:AUTO_FIX")
	Do $$$AssertTrue(tStory.steps.%Get(3).text [ "did not accept AUTO_FIX: fix changes PID-7.", tStory.steps.%Get(3).text)
	Do $$$AssertEquals(tStory.steps.%Get(4).status, "waiting")
	Do $$$AssertTrue(tStory.steps.%Get(1).text [ "no instruction-like text", "no flags")
}

/// A plug-in row (Namespace LEGACY): the story reads the header and masked body in LEGACY, links
/// Visual Trace there, and ignores an IRISAPP Usage row that has the same header ID.
Method TestStoryOtherNamespace()
{
	Set tNS = ##class(AgenticProd.Setup).#LEGACYNS
	Do $$$AssertStatusOK(..StubHeader(tNS, .tHeader, .tMsgId), "stub header in "_tNS)
	Quit:$GET(tHeader)=""
	Do $$$AssertStatusOK(..AddLogRow(tHeader, "ESCALATE", "SENT_FOR_APPROVAL", "", "", "", .tLogId))
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(tLogId)
	Set tLog.Namespace = tNS, tLog.SessionId = tHeader
	Do $$$AssertStatusOK(tLog.%Save())
	// Same header ID, this namespace: must not be read as the plug-in row's agent run
	Do $$$AssertStatusOK(..AddUsageRow(tHeader, "MAP_CODE", "gpt-4o-mini", 0, ""))

	Set tStory = ##class(AgenticProd.UI.REST).StoryData(tLogId)
	Do $$$AssertEquals(tStory.namespace, tNS)
	Do $$$AssertTrue(tStory.traceUrl [ ("/"_$ZCONVERT(tNS, "L")_"/EnsPortal.VisualTrace.zen"), tStory.traceUrl)
	Do $$$AssertTrue(tStory.message [ "GLU1", "body read in "_tNS)
	Do $$$AssertTrue(tStory.message '[ "STUBPATIENT", "PID-5 masked")
	Do $$$AssertTrue(tStory.steps.%Get(2).text [ "not used", "IRISAPP Usage row ignored: "_tStory.steps.%Get(2).text)
	Set tRows = ##class(AgenticProd.UI.REST).DecisionsData(10, 0), tFound = ""
	For i = 0:1:tRows.%Size() - 1 Set:tRows.%Get(i).ID=tLogId tFound = tRows.%Get(i)
	Do $$$AssertTrue($IsObject(tFound), "row listed")
	If $IsObject(tFound) {
		Do $$$AssertEquals(tFound.Namespace, tNS)
		Do $$$AssertEquals(tFound.traceUrl, tStory.traceUrl)
		Do $$$AssertEquals(tFound.agentCalled, 0, "Usage of the other namespace not counted")
		Do $$$AssertEquals(tFound.ControlId, "", "TriageRequest bodies of another namespace are not joined")
	}

	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE ID = ?", tLogId)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.Usage WHERE HeaderId = ? AND EvalRunId IS NULL AND Model = 'gpt-4o-mini' AND PromptTokens = 0", tHeader)
	Do ..DropStubHeader(tNS, tHeader, tMsgId)
}

/// Synthetic HL7 message and header saved in pNamespace.
ClassMethod StubHeader(pNamespace As %String, Output pHeader As %String, Output pMsgId As %String) As %Status
{
	Set (pHeader, pMsgId) = ""
	New $NAMESPACE
	Set tSC = $$$OK
	Try {
		Set $NAMESPACE = pNamespace
		Set tText = "MSH|^~\&|LIS|LAB|EHR|HOSP|20261030101500||ORU^R01|STUBNS1|P|2.5.1"_$CHAR(13)
			_"PID|1||MRN-NS-1^^^LAB^MR||STUBPATIENT^NSTEST||19800101|F"_$CHAR(13)
			_"OBX|1|NM|GLU1^Glucose^L||5.4|mmol/L|||||F"_$CHAR(13)
		Set tMsg = ##class(EnsLib.HL7.Message).ImportFromString(tText, .tSC)
		$$$ThrowOnError(tSC)
		$$$ThrowOnError(tMsg.%Save())
		Set tHdr = ##class(Ens.MessageHeader).%New()
		Set tHdr.MessageBodyClassName = "EnsLib.HL7.Message", tHdr.MessageBodyId = tMsg.%Id()
		$$$ThrowOnError(tHdr.%Save())
		Set tHdr.SessionId = tHdr.%Id()
		$$$ThrowOnError(tHdr.%Save())
		Set pHeader = tHdr.%Id(), pMsgId = tMsg.%Id()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod DropStubHeader(pNamespace As %String, pHeader As %String, pMsgId As %String)
{
	New $NAMESPACE
	Set $NAMESPACE = pNamespace
	Do ##class(Ens.MessageHeader).%DeleteId(pHeader)
	Do ##class(EnsLib.HL7.Message).%DeleteId(pMsgId)
}

/// Metrics on stub rows (eval run RUNID, so they show with eval included only): tokens split so the
/// parts add up, quantiles, tool and validate_fix counts, decision groups, saved calls, steps.
Method TestMetricsSummary()
{
	Set tBefore = ##class(AgenticProd.UI.REST).MetricsData(1)
	Do $$$AssertTrue($IsObject(tBefore.outcomes) && $IsObject(tBefore.agentVsFinal), "outcomes and agentVsFinal present")
	Set tModel = "test-metrics-model", tSession = "test-metrics-9351"
	For i = 1:1:4 {
		Set tUsage = ##class(AgenticProd.Data.Usage).%New()
		Set tUsage.HeaderId = -9350 - i, tUsage.EvalRunId = ..#RUNID, tUsage.Model = tModel, tUsage.Decision = "MAP_CODE"
		Set tUsage.PromptTokens = 1000, tUsage.CacheReadTokens = 400, tUsage.CompletionTokens = 100, tUsage.ReasoningTokens = 30
		Set tUsage.TotalMs = i * 1000, tUsage.CostUsd = .001, tUsage.AgentSessionId = $SELECT(i = 1: tSession, 1: "")
		Do $$$AssertStatusOK(tUsage.%Save())
	}
	// Replays repeat a recorded run: left out of tokens and latency
	Do $$$AssertStatusOK(..AddUsageRow(-9355, "MAP_CODE", tModel, 1, ..#RUNID))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("validate_fix", {}, "OK", 10, 50, "", -9351, tSession, , "PASS"))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("validate_fix", {}, "OK", 30, 50, "", -9351, tSession, , "FAIL"))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.ToolCall).Log("apply_fix", {}, "DENIED", "", "", "read-only", -9351, tSession))
	Do $$$AssertStatusOK(..AddLogRow(-9361, "AUTO_FIX", "APPLIED"))
	Do $$$AssertStatusOK(..AddLogRow(-9362, "ESCALATE", "DOWNGRADED:AUTO_FIX"))
	Do $$$AssertStatusOK(..AddLogRow(-9363, "REJECT", "REJECTED"))
	Set tSaved = ##class(AgenticProd.Data.SavedCall).%New()
	Set tSaved.HeaderId = -9364, tSaved.LocalCodes = "GLU-01", tSaved.EvalRunId = ..#RUNID
	Do $$$AssertStatusOK(tSaved.%Save())
	For tMs = 10, 20, 30 Do $$$AssertStatusOK(##class(AgenticProd.Data.Span).Log("feedfeedfeedfeedfeedfeedfeedfeed", "00000000000000b"_(tMs/10), "", "router check", ##class(AgenticProd.Telemetry.Trace).ZtsBefore(tMs), $ZTIMESTAMP, "Ok", {}, -9365, "EV"_..#RUNID_"-T"))

	Set tM = ##class(AgenticProd.UI.REST).MetricsData(1)
	For i = 0:1:tM.tokens.%Size() - 1 Set:tM.tokens.%Get(i).Model=tModel tTok = tM.tokens.%Get(i)
	Do $$$AssertTrue($DATA(tTok), "model row, case kept")
	Quit:'$DATA(tTok)
	Do $$$AssertEquals(tTok.Runs, 4, "replay left out")
	Do $$$AssertEquals(tTok.InputTokens, 2400, "prompt minus cache reads")
	Do $$$AssertEquals(tTok.CachedInputTokens, 1600)
	Do $$$AssertEquals(tTok.OutputTokens, 280, "completion minus reasoning")
	Do $$$AssertEquals(tTok.ReasoningTokens, 120)
	For i = 0:1:tM.latency.%Size() - 1 Set:tM.latency.%Get(i).model=tModel tLat = tM.latency.%Get(i)
	Do $$$AssertEquals(tLat.count, 4)
	Do $$$AssertEquals(tLat.p50, 2, "nearest rank of 1,2,3,4 s")
	Do $$$AssertEquals(tLat.p95, 4)
	For i = 0:1:tM.tools.%Size() - 1 Set tTool(tM.tools.%Get(i).Tool) = tM.tools.%Get(i)
	For i = 0:1:tBefore.tools.%Size() - 1 Set tToolBefore(tBefore.tools.%Get(i).Tool) = tBefore.tools.%Get(i).Calls
	Do $$$AssertEquals(tTool("validate_fix").Calls - $GET(tToolBefore("validate_fix")), 2, "tool name case kept")
	Do $$$AssertTrue(tTool("apply_fix").Denied >= 1, "denied counted")
	For i = 0:1:tM.validateFix.%Size() - 1 Set tV(tM.validateFix.%Get(i).Verdict) = tM.validateFix.%Get(i).Calls
	For i = 0:1:tBefore.validateFix.%Size() - 1 Set tVB(tBefore.validateFix.%Get(i).Verdict) = tBefore.validateFix.%Get(i).Calls
	Do $$$AssertEquals(tV("PASS") - $GET(tVB("PASS")), 1)
	Do $$$AssertEquals(tV("FAIL") - $GET(tVB("FAIL")), 1)
	Do $$$AssertEquals(..Sum(tM.decisionMix.applied) - ..Sum(tBefore.decisionMix.applied), 1)
	Do $$$AssertEquals(..Sum(tM.decisionMix.approval) - ..Sum(tBefore.decisionMix.approval), 1, "DOWNGRADED goes to a person")
	Do $$$AssertEquals(..Sum(tM.decisionMix.rejected) - ..Sum(tBefore.decisionMix.rejected), 1)
	Do $$$AssertEquals(tM.decisionMix.hours.%Size(), 24)
	Do $$$AssertEquals(tM.unsafeBlocked - tBefore.unsafeBlocked, 1)
	Do $$$AssertEquals(tM.saved.calls - tBefore.saved.calls, 1)
	Do $$$AssertTrue(tM.saved.basedOnRuns >= 4, "saving priced from live MAP_CODE runs")
	For i = 0:1:tM.steps.%Size() - 1 Set:tM.steps.%Get(i).step="router check" tStep = tM.steps.%Get(i)
	Do $$$AssertTrue($IsObject($GET(tStep)), "router step")
	Set tLive = ##class(AgenticProd.UI.REST).MetricsData(0)
	For i = 0:1:tLive.tokens.%Size() - 1 Do $$$AssertNotEquals(tLive.tokens.%Get(i).Model, tModel, "eval rows out of live metrics")
	Do $$$AssertEquals(tLive.saved.calls, ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall WHERE EvalRunId IS NULL").%Get(0).N)
}

Method TestOutcomeGroup()
{
	For tPair = "APPLIED:applied", "SENT_FOR_APPROVAL:approval", "APPROVED:approval", "DOWNGRADED:AUTO_FIX:approval", "REVIEW_REJECTED:approval", "REJECTED:rejected", "RESENT:resent", "ERROR:AUTO_FIX:other", ":other" {
		Do $$$AssertEquals(##class(AgenticProd.UI.REST).OutcomeGroup($PIECE(tPair, ":", 1, *-1)), $PIECE(tPair, ":", *), tPair)
	}
}

/// Verdict from validate_fix's result as Policy.Audit and the session hold it.
Method TestVerdictOf()
{
	Do $$$AssertEquals(##class(AgenticProd.Data.ToolCall).VerdictOf("<untrusted_data source=""validate_fix"">{""result"":""PASS_NEEDS_REVIEW"",""errors"":[]}</untrusted_data>"), "PASS_NEEDS_REVIEW")
	Do $$$AssertEquals(##class(AgenticProd.Data.ToolCall).VerdictOf("""{""result"":""FAIL"",""errors"":[]}"""), "FAIL", "JSON-escaped")
	Do $$$AssertEquals(##class(AgenticProd.Data.ToolCall).VerdictOf("no verdict here"), "")
}

ClassMethod Sum(pArray As %DynamicArray) As %Integer
{
	Set tSum = 0, tIter = pArray.%GetIterator()
	While tIter.%GetNext(, .tV) {
		Set tSum = tSum + tV
	}
	Quit tSum
}

/// Values masking hides, with their components, are replaced in any text shown.
Method TestMask()
{
	Do ##class(AgenticProd.UI.REST).AddSecret("DOE^JANE^Q", "^~&", .tSecrets)
	Do ##class(AgenticProd.UI.REST).AddSecret("19800101", "^~&", .tSecrets)
	Set tText = ##class(AgenticProd.UI.REST).Mask("PID-5 DOE^JANE^Q, born 19800101, DOE again; Q stays", .tSecrets)
	Do $$$AssertEquals(tText, "PID-5 ***, born ***, *** again; Q stays")
}

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
	Do $$$AssertEquals(..Get("api/decisions/0/story", tUser, tPass).HttpResponse.StatusCode, 404, "unknown decision")
	Do $$$AssertEquals(..Get("api/metrics/summary?eval=1", tUser, tPass).HttpResponse.StatusCode, 200, "metrics")
	Do $$$AssertEquals(..Get("vendor/echarts/echarts.min.js", tUser, tPass).HttpResponse.StatusCode, 200, "charts library served locally")
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

/// Stub DecisionLog row; an eval row (RUNID) unless pEvalRunId is "".
Method AddLogRow(pHeader As %Integer, pDecision As %String, pOutcome As %String, pEvalRunId As %String = {..#RUNID}, pJSON As %String = "", pReason As %String = "", Output pId As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tRow.HeaderId = pHeader, tRow.Decision = pDecision, tRow.ErrorClass = "OTHER"
	Set tRow.EvalRunId = pEvalRunId, tRow.CaseId = $SELECT(pEvalRunId '= "": "T", 1: ""), tRow.Outcome = pOutcome, tRow.Confidence = .5
	Set tRow.DecisionJSON = pJSON, tRow.Reason = pReason
	Set tSC = tRow.%Save(), pId = tRow.%Id()
	Quit tSC
}

/// Stub Usage row with no tokens, so TokensUsedToday is unchanged.
Method AddUsageRow(pHeader As %Integer, pDecision As %String, pModel As %String, pReplay As %Boolean, pEvalRunId As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.Usage).%New()
	Set tRow.HeaderId = pHeader, tRow.Decision = pDecision, tRow.Model = pModel, tRow.Replay = pReplay
	Set tRow.EvalRunId = pEvalRunId, tRow.PromptTokens = 0, tRow.CompletionTokens = 0, tRow.CostUsd = .001
	Quit tRow.%Save()
}

Method OnAfterOneTest() As %Status
{
	For tTable = "DecisionLog", "Usage", "Span", "SavedCall" {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data."_tTable_" WHERE EvalRunId = ? OR HeaderId BETWEEN -9399 AND -9300", ..#RUNID)
	}
	// ToolCall has no EvalRunId column
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.ToolCall WHERE HeaderId BETWEEN -9399 AND -9300")
	Quit $$$OK
}

}
