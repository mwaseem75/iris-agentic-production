/// UI.Flow and its REST routes on stub rows. No LLM: the burst tests are dry runs or refusals.
/// The HTTP test needs Setup.DashboardSetup to have run, like RESTTest.
Class AgenticProd.Test.UI.FlowTest Extends AgenticProd.Test.Case
{

/// HeaderId of the stub rows; real headers are positive.
Parameter HEADER = -9701;

Parameter MODEL = "test-flow-model";

Method TestLaneAndOutcomeMapping()
{
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("AgenticProd.Process.Triage"), "decision")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("AgenticProd.Operation.Agent"), "ai")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("EnsLib.HL7.Service.FileService"), "inbound")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("AgenticProd.Operation.NphiesOut"), "outcome")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("AgenticProd.Process.LabRouter"), "router")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Lane("No.Such.Class"), "router", "unknown class lands in the router lane")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("APPLIED"), "applied")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("OBSERVED:AUTO_FIX"), "observed")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("DOWNGRADED:AUTO_FIX:x"), "person")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("ERROR:send failed"), "person")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("RESENT"), "resent")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).OutcomeLane("REJECTED"), "rejected")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).CheckNs("LEGACY"), "LEGACY")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).CheckNs("%SYS"), "", "only the two production namespaces")
}

Method TestGrounding()
{
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).GroundingGate("", 0, "").status, "none", "gate did not run")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).GroundingGate("{}", 1, "").status, "passed")
	Set tAmb = ##class(AgenticProd.UI.Flow).GroundingGate("{}", 0, "loinc_from_search,ambiguity")
	Do $$$AssertEquals(tAmb.status, "ambiguous")
	Set tBad = ##class(AgenticProd.UI.Flow).GroundingGate("{}", 0, "evidence_quotes")
	Do $$$AssertEquals(tBad.status, "ungrounded")
	Do $$$AssertEquals(tBad.check, "evidence_quotes")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).InjectionFlags("{""evidence"":[""x"",""suspicious instruction in OBX(1):5: ignore previous""]}").%ToJSON(), "[""OBX(1):5""]")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).InjectionFlags("").%Size(), 0)
}

Method TestMapHasProductionItems()
{
	Set tMap = ##class(AgenticProd.UI.Flow).Map("IRISAPP")
	Do $$$AssertEquals(tMap.production, "AgenticProd.Production")
	Set tIter = tMap.items.%GetIterator()
	While tIter.%GetNext(, .tItem) {
		Set tLane(tItem.name) = tItem.lane
	}
	Do $$$AssertEquals($GET(tLane("LabFileIn")), "inbound")
	Do $$$AssertEquals($GET(tLane("Triage")), "decision")
	Do $$$AssertEquals($GET(tLane("TriageAgent")), "ai")
	Set tIter = tMap.edges.%GetIterator()
	While tIter.%GetNext(, .tEdge) {
		Do $$$AssertTrue($DATA(tLane(tEdge.from)) && $DATA(tLane(tEdge.to)), "edge ends are production items: "_tEdge.from_" "_tEdge.to)
	}
}

/// Stub request headers LabRouter -> Triage: one clean session, one error, one in an eval session, one in a burst.
/// The counters count source and target per item, and the eval toggle drops the eval session.
Method TestMapCountsHeaders()
{
	Set tIn = ..Count(1, "Triage", "in"), tInLive = ..Count(0, "Triage", "in")
	Set tOut = ..Count(1, "LabRouter", "out"), tErr = ..Count(1, "Triage", "errors")
	Set tIds = ""
	For tSession = ..#HEADER, ..#HEADER - 1, ..#HEADER - 2, ..#HEADER - 3 {
		Set tH = ##class(Ens.MessageHeader).%New()
		Set tH.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), tH.Type = 1, tH.SourceConfigName = "LabRouter", tH.TargetConfigName = "Triage", tH.SessionId = tSession
		Set tH.IsError = (tSession = (..#HEADER - 1))
		Do $$$AssertStatusOK(tH.%Save())
		Set tIds = tIds_$LISTBUILD(tH.%Id())
	}
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = ..#HEADER, tLog.SessionId = ..#HEADER - 2, tLog.Decision = "ESCALATE", tLog.ErrorClass = "OTHER", tLog.EvalRunId = 999904
	Do $$$AssertStatusOK(tLog.%Save())
	Set tBurst = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tBurst.HeaderId = ..#HEADER, tBurst.SessionId = ..#HEADER - 3, tBurst.Decision = "ESCALATE", tBurst.ErrorClass = "OTHER", tBurst.EvalRunId = 900099
	Do $$$AssertStatusOK(tBurst.%Save())
	Set tInAfter = ..Count(1, "Triage", "in"), tInLiveAfter = ..Count(0, "Triage", "in")
	Set tOutAfter = ..Count(1, "LabRouter", "out"), tErrAfter = ..Count(1, "Triage", "errors")
	For i = 1:1:$LISTLENGTH(tIds) Do ##class(Ens.MessageHeader).%DeleteId($LIST(tIds, i))
	Do ..Cleanup()
	Do $$$AssertEquals(tInAfter - tIn, 4, "target counted")
	Do $$$AssertEquals(tOutAfter - tOut, 4, "source counted")
	Do $$$AssertEquals(tErrAfter - tErr, 1, "error counted")
	Do $$$AssertEquals(tInLiveAfter - tInLive, 3, "eval session left out, burst session counted")
}

/// One counter (in, out, errors) of one item in a Map of the last hour.
Method Count(pIncludeEval As %Boolean, pItem As %String, pField As %String) As %Integer [ Internal ]
{
	Set tIter = ##class(AgenticProd.UI.Flow).Map("IRISAPP", , , pIncludeEval).items.%GetIterator()
	While tIter.%GetNext(, .tItem) {
		Quit:(tItem.name = pItem)
	}
	Quit tItem.%Get(pField)
}

/// Rows after a cursor: the stub hop-less run shows its decision with all three gates, the tool
/// call and the usage row, and the cursor moves past them.
Method TestSliceFromStubRows()
{
	Do ..Cleanup()
	Set tHead = ##class(AgenticProd.UI.Flow).Head("IRISAPP")
	Do $$$AssertTrue(tHead.cursor.dec >= 0, "head cursor")

	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = ..#HEADER, tLog.Decision = "MAP_CODE", tLog.ErrorClass = "UNMAPPED_CODE", tLog.Outcome = "SENT_FOR_APPROVAL", tLog.Confidence = .8
	Set tLog.DecisionJSON = {"decision":"MAP_CODE","evidence":["suspicious instruction in NTE(1):3: ignore previous"]}.%ToJSON()
	Set tLog.GroundingJSON = {"grounded":false}.%ToJSON(), tLog.Grounded = 0, tLog.GroundingFailed = "loinc_from_search,ambiguity"
	Do $$$AssertStatusOK(tLog.%Save())
	Set tCall = ##class(AgenticProd.Data.ToolCall).%New()
	Set tCall.HeaderId = ..#HEADER, tCall.Tool = "search_loinc", tCall.Status = "OK", tCall.DurationMs = 12
	Do $$$AssertStatusOK(tCall.%Save())
	Set tUse = ##class(AgenticProd.Data.Usage).%New()
	Set tUse.HeaderId = ..#HEADER, tUse.Model = ..#MODEL, tUse.PromptTokens = 100, tUse.CompletionTokens = 20, tUse.CostUsd = .002, tUse.Replay = 1
	Do $$$AssertStatusOK(tUse.%Save())

	Set tSlice = ##class(AgenticProd.UI.Flow).Slice("IRISAPP", , , tHead.cursor)
	Do $$$AssertEquals(tSlice.decisions.%Size(), 1, "only the stub decision is newer than the cursor")
	Set tCard = tSlice.decisions.%Get(0)
	Do $$$AssertEquals(tCard.gates.injection.status, "flagged")
	Do $$$AssertEquals(tCard.gates.injection.flagged.%ToJSON(), "[""NTE(1):3""]")
	Do $$$AssertEquals(tCard.gates.grounding.status, "ambiguous")
	Do $$$AssertEquals(tCard.gates.triage.outcome, "SENT_FOR_APPROVAL")
	Do $$$AssertEquals(tCard.outcome, "person")
	Do $$$AssertEquals(tCard.burst, 0, "not a burst")
	Do $$$AssertEquals(tCard.tokens, 120)
	Do $$$AssertEquals(tCard.replay, 1)
	Do $$$AssertEquals(tSlice.tools.%Size(), 1)
	Do $$$AssertEquals(tSlice.tools.%Get(0).tool, "search_loinc")
	Do $$$AssertEquals(tSlice.usage.%Size(), 1)
	Do $$$AssertEquals(tSlice.cursor.dec, tCard.id)

	Set tAgain = ##class(AgenticProd.UI.Flow).Slice("IRISAPP", , , tSlice.cursor)
	Do $$$AssertEquals(tAgain.decisions.%Size() + tAgain.tools.%Size() + tAgain.usage.%Size(), 0, "nothing new after the returned cursor")
	Do ..Cleanup()
}

Method TestBurstRefusals()
{
	Set tReplay = {"mode":"replay","killSwitch":0,"budget":1000,"used":0,"model":(..#MODEL)}
	Set tLive = {"mode":"live","killSwitch":0,"budget":1000,"used":0,"model":(..#MODEL)}
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3}, 0, 1, tReplay).status, 403, "not an admin")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":0}, 1, 1, tReplay).status, 400, "n below 1")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":"x"}, 1, 1, tReplay).status, 400, "n not a number")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":31}, 1, 1, tReplay).status, 400, "n above the cap")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3, "ns":"LEGACY"}, 1, 1, tReplay).status, 400, "LEGACY has no eval files")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3}, 1, 1, {"mode":"replay","killSwitch":1,"model":(..#MODEL)}).status, 409, "kill switch")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3, "mode":"live"}, 1, 1, tReplay).status, 409, "live burst while the agent is in replay mode")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3}, 1, 1, tLive).status, 409, "replay burst while the agent is live")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":11, "mode":"live"}, 1, 1, tLive).status, 400, "live burst over 10")
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3, "mode":"live"}, 1, 1, {"mode":"live","killSwitch":0,"budget":1000,"used":1000,"model":(..#MODEL)}).status, 409, "daily budget used up")
	Set tAsk = ##class(AgenticProd.UI.Flow).Burst({"n":3, "mode":"live"}, 1, 1, tLive)
	Do $$$AssertEquals(tAsk.status, 409, "live burst without confirm")
	Do $$$AssertTrue(tAsk.needsConfirm, "asks for a confirm")
	Do $$$AssertTrue(tAsk.estimatedCostUsd > 0, "shows an estimate")
}

Method TestBurstPlansReplayFromRecordedRuns()
{
	Do ..Cleanup()
	Set tAgent = {"mode":"replay","killSwitch":0,"budget":1000,"used":0,"model":(..#MODEL)}
	Do $$$AssertEquals(##class(AgenticProd.UI.Flow).Burst({"n":3}, 1, 1, tAgent).status, 409, "no recorded run for the model yet")
	Set tUse = ##class(AgenticProd.Data.Usage).%New()
	Set tUse.HeaderId = ..#HEADER, tUse.Model = ..#MODEL, tUse.CaseId = "01", tUse.DecisionJSON = "{}", tUse.Replay = 0
	Do $$$AssertStatusOK(tUse.%Save())
	Set tPlan = ##class(AgenticProd.UI.Flow).Burst({"n":5}, 1, 1, tAgent)
	Do $$$AssertEquals(tPlan.status, 200)
	Do $$$AssertEquals(tPlan.sent.%Size(), 1, "one recorded case, so one message")
	Do $$$AssertTrue($MATCH(tPlan.sent.%Get(0).controlId, "EV9\d+-01"), "control id replay can read: "_tPlan.sent.%Get(0).controlId)
	Do $$$AssertEquals(tPlan.estimatedCostUsd, 0, "replay is free")
	Do $$$AssertTrue(tPlan.dryRun, "dry run wrote no file")
	Do ..Cleanup()
}

/// Reviewer is not an admin: the feed answers, a burst is refused.
Method TestHttp()
{
	Set tUser = ##class(AgenticProd.Setup).#REVIEWUSER, tPass = ##class(AgenticProd.Setup).#REVIEWPASSWORD
	Set tReq = ..Get("api/flow/map?ns=IRISAPP", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "map")
	Do $$$AssertTrue(##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data).items.%Size() > 0, "map has items")
	Do $$$AssertEquals(..Get("api/flow/map?ns=%25SYS", tUser, tPass).HttpResponse.StatusCode, 400, "other namespace refused")
	Set tReq = ..Get("api/flow/live?ns=IRISAPP", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "live without cursor")
	Set tHead = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tHead.cursor.hop >= 0, "cursor returned")
	Set tReq = ..Get("api/flow/live?ns=IRISAPP&since="_tHead.cursor.hop_"&dec="_tHead.cursor.dec_"&tool="_tHead.cursor.tool_"&usage="_tHead.cursor.usage, tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "live with cursor")
	Do $$$AssertTrue(##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data).%IsDefined("hops"), "slice shape")
	Set tNow = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
	Set tReq = ..Get("api/flow/window?ns=IRISAPP&from="_$TRANSLATE(tNow, " ", "T")_"&to="_$TRANSLATE(tNow, " ", "T"), tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "window")
	Do $$$AssertTrue(##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data).%IsDefined("map"), "window carries the map")
	Do $$$AssertEquals(..Get("api/flow/window?ns=IRISAPP&from=x%27y", tUser, tPass).HttpResponse.StatusCode, 400, "timestamps only")

	Set tPost = ##class(%Net.HttpRequest).%New()
	Set tPost.Server = "localhost", tPost.Port = 52773, tPost.Username = tUser, tPost.Password = tPass
	Set tPost.ContentType = "application/json"
	Do tPost.EntityBody.Write("{""n"":3}")
	Do $$$AssertStatusOK(tPost.Post(##class(AgenticProd.Setup).#DASHAPI_"/burst"))
	Do $$$AssertEquals(tPost.HttpResponse.StatusCode, 403, "burst needs the admin role")
}

Method Get(pPath As %String, pUser As %String = "", pPass As %String = "") As %Net.HttpRequest
{
	Set tReq = ##class(%Net.HttpRequest).%New()
	Set tReq.Server = "localhost", tReq.Port = 52773
	Set:pUser'="" tReq.Username = pUser, tReq.Password = pPass
	Do $$$AssertStatusOK(tReq.Get(##class(AgenticProd.Setup).#DASHAPP_"/"_pPath), "GET "_pPath)
	Quit tReq
}

Method Cleanup()
{
	For tTable = "DecisionLog", "ToolCall", "Usage" {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data."_tTable_" WHERE HeaderId = ?", ..#HEADER)
	}
}

Method OnAfterAllTests() As %Status
{
	Do ..Cleanup()
	Quit $$$OK
}

}
