Include Ensemble

/// Acts on the triage agent's Decision for one failed message; the only component that does.
/// The agent only proposes: whatever the action matrix does not allow becomes ESCALATE, and an
/// AUTO_FIX is re-checked here, never taken on the agent's word. The original body is never changed.
/// Format-neutral: fixes are re-checked by the format class named in CHECKERS.
Class AgenticProd.Process.Triage Extends Ens.BusinessProcess
{

/// TriageRequest.Format = class with ClassMethods CheckFix(body, fixArray, .result, .fixedCopy)
/// and GroundingProblems(body, decision, kbRow, checks), see Tools.HL7.
Parameter CHECKERS = "HL7v2=AgenticProd.Tools.HL7";

/// Error classes only the sender can fix, so REJECT is allowed for them alone.
Parameter REJECTABLE = ",STRUCTURE_ERROR,ROUTING,";

/// Task action Eval.Runner closes its own approval tasks with. Review then leaves the eval
/// row's outcome as scored and acts on nothing; on a live row it counts as a reject.
Parameter EVALACTION = "Eval";

/// Agent operation that answers a TriageRequest with a Decision.
Property AgentTarget As Ens.DataType.ConfigName [ InitialExpression = "AgenticProd.Operation.Agent" ];

/// Seconds to wait for the agent; the provider has no timeout of its own.
Property AgentTimeout As %Integer(MINVAL = 1) [ InitialExpression = 120 ];

/// Where the new, fixed message goes after an AUTO_FIX, and where an approved mapping resends the
/// failed message. Empty (plug-in installs): the failed message's own target.
Property TargetConfigName As Ens.DataType.ConfigName;

/// Workflow operation (role) that gets an ApprovalTask for every MAP_CODE and ESCALATE.
Property ApprovalTarget As Ens.DataType.ConfigName;

/// Lowest agent confidence accepted for AUTO_FIX.
Property AutoFixThreshold As %Numeric(MAXVAL = 1, MINVAL = 0) [ InitialExpression = 0.85 ];

/// Folder for rejected messages and their reason files.
Property RejectPath As %String(MAXLEN = 500) [ InitialExpression = {##class(AgenticProd.Paths).Dir("data/rejected/")} ];

/// Export the trace of each failed message over OTLP (see Telemetry.Trace). Spans are stored in
/// Data.Span either way.
Property TracingEnabled As %Boolean [ InitialExpression = 0 ];

/// Error classes whose AUTO_FIX is switched off on the Settings tab, comma separated: such a
/// proposal goes to a person.
Property AutoFixDisabled As %String(MAXLEN = 500);

/// How the grounding gate treats a claim it cannot trace to the message, a tool result or the
/// KB: off, warn (record it and show it to the reviewer) or enforce (ESCALATE, proposal kept).
Property GroundingStrictness As %String(VALUELIST = ",off,warn,enforce") [ InitialExpression = "enforce" ];

/// observe: decide and log what would be done (Outcome OBSERVED:<outcome>) but send, resend,
/// reject and ask nobody. propose: every decision goes to a person (Outcome PROPOSED:<outcome>
/// for what act would have done alone). act: the full action matrix.
Property ActionMode As %String(VALUELIST = ",observe,propose,act") [ InitialExpression = "act" ];

/// Lookup table an approved mapping is written to (the production's own code table).
Property CodeTable As %String(MAXLEN = 128) [ InitialExpression = "LabCodeMap" ];

/// Value an approved mapping writes: "loinc^display" (LabCodeMap) or "loinc" (a table whose
/// readers expect the bare code, like LegacyLabCodes).
Property CodeTableFormat As %String(VALUELIST = ",loinc^display,loinc") [ InitialExpression = "loinc^display" ];

Parameter SETTINGS = "AgentTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ApprovalTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},AutoFixThreshold:Triage,AutoFixDisabled:Triage,GroundingStrictness:Triage,ActionMode:Triage,CodeTable:Triage,CodeTableFormat:Triage,AgentTimeout:Triage,RejectPath:Triage,TracingEnabled:Tracing";

/// Ask the agent, apply the action matrix, act, and log what was done in Data.DecisionLog.
/// pResponse is the decision Triage acted on (the agent's, or its ESCALATE downgrade).
Method OnRequest(pRequest As AgenticProd.Msg.TriageRequest, Output pResponse As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Set (tRoot, tOutcome) = ""
	Try {
		// Spans are always stored in Data.Span; TracingEnabled adds the OTLP export
		Set tRoot = ##class(AgenticProd.Telemetry.Trace).TriageRoot(pRequest, ..TracingEnabled)
		Set pRequest.TraceParent = ##class(AgenticProd.Telemetry.Trace).Context(tRoot)
		// Saved so the workflow answer, which may come in another job, joins the trace
		If pRequest.TraceParent '= "" $$$ThrowOnError(pRequest.%Save())
		Set tDecision = ""
		If ..FixedByTriage(pRequest.HeaderId) {
			// Our own fix failed again: another agent round could loop, so a person decides
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "message built by a Triage AUTO_FIX failed again; agent not called a second time")
		} ElseIf ..CheckerFor(pRequest.Format) = "" {
			// No skill or fix checker for this format yet (FHIR until F2): an agent run would be spent for nothing
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "no fix checker for format '"_pRequest.Format_"'; agent not called")
		} Else {
			Set tAgentStart = $ZTIMESTAMP
			Set tSC = ..SendRequestSync(..AgentTarget, pRequest, .tDecision, ..AgentTimeout)
			Set tAgentEnd = $ZTIMESTAMP
		}
		Set tNoAnswer = ""
		If $$$ISERR(tSC) || '$IsObject(tDecision) {
			Set tNoAnswer = $SELECT($$$ISERR(tSC): $SYSTEM.Status.GetErrorText(tSC), 1: "timed out after "_..AgentTimeout_" s")
			// No answer still ends with a person looking at the message, never a drop
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "agent gave no decision: "_tNoAnswer)
			Set tSC = $$$OK
		}
		// Agent and tool spans come from the run's Usage and ToolCall rows: the agent job itself
		// loads no OTel library (a live run with spans in that job ended in a segfault once)
		If $DATA(tAgentStart) Do ##class(AgenticProd.Telemetry.Trace).AgentSpans(pRequest.TraceParent, pRequest, $SELECT(tNoAnswer = "": tDecision, 1: ""), tAgentStart, tAgentEnd, tNoAnswer)
		Set tPlanStart = $ZTIMESTAMP
		// Only an agent's own answer is checked; a system ESCALATE (budget, kill switch) has no claims
		Set tCheck = (tNoAnswer = "") && $DATA(tAgentStart) && ((tDecision.AgentSessionId '= "") || (tDecision.Decision '= "ESCALATE"))
		$$$ThrowOnError(..Decide(pRequest, tDecision, tCheck, .pResponse, .tOutcome, .tFixed, .tGrounding))
		Set tOutcome = ..ModeOutcome(tOutcome)
		// Logged before the send: the row ID is the approval task's completion key
		$$$ThrowOnError(##class(AgenticProd.Data.DecisionLog).Record(pRequest, pResponse, .tLogId, tOutcome, $SELECT(tOutcome = "APPLIED": tFixed, 1: ""), tGrounding))
		Set tSendSC = ..Dispatch(pRequest, pResponse, tOutcome, tFixed, tLogId)
		If $$$ISERR(tSendSC) $$$ThrowOnError(..SetOutcome(tLogId, "ERROR:"_tOutcome))
		Do ##class(AgenticProd.Telemetry.Trace).DecisionSpan(pRequest.TraceParent, tDecision, pResponse, tOutcome, tPlanStart, $$$ISERR(tSendSC), tGrounding)
		$$$TRACE("Triage header "_pRequest.HeaderId_": agent "_tDecision.Decision_", outcome "_tOutcome)
		$$$ThrowOnError(tSendSC)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	If $IsObject(tRoot) {
		Set tAttrs("agentic.final_outcome") = tOutcome
		Set:$IsObject($GET(pResponse)) tAttrs("agentic.decision") = pResponse.Decision
		Do ##class(AgenticProd.Telemetry.Trace).End(tRoot, $SELECT($$$ISERR(tSC): "Error", 1: "Ok"), .tAttrs)
	}
	Quit tSC
}

/// What ActionMode makes of Plan's outcome: observe only logs it (OBSERVED:x); propose sends
/// what act would do on its own to a person first (PROPOSED:x); act keeps it.
Method ModeOutcome(pOutcome As %String) As %String
{
	Quit:..ActionMode="observe" "OBSERVED:"_pOutcome
	Quit:(..ActionMode="propose")&&$LISTFIND($LISTBUILD("APPLIED", "RESENT", "REJECTED"), pOutcome) "PROPOSED:"_pOutcome
	Quit pOutcome
}

/// Grounding gate (when pCheck) then the action matrix; Plan's outputs plus pGrounding (Ground's
/// result, "" when not checked). In warn mode a failure only adds an "ungrounded" evidence line;
/// in enforce mode Plan downgrades the proposal too. Sends nothing and logs nothing.
Method Decide(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pCheck As %Boolean, Output pFinal As AgenticProd.Msg.Decision, Output pOutcome As %String, Output pFixed As %Persistent, Output pGrounding As %DynamicObject) As %Status
{
	Set (pGrounding, tUngrounded) = ""
	Set tSC = $$$OK
	Try {
		If pCheck {
			$$$ThrowOnError(..Ground(pRequest, pDecision, .pGrounding))
			Set:$IsObject(pGrounding)&&'pGrounding.grounded&&(..GroundingStrictness'="warn") tUngrounded = pGrounding.summary
		}
		$$$ThrowOnError(..Plan(pRequest, pDecision, .pFinal, .pOutcome, .pFixed, tUngrounded))
		If $IsObject(pGrounding) && 'pGrounding.grounded Do pFinal.Evidence.Insert("ungrounded ("_..GroundingStrictness_" mode): "_pGrounding.summary)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Apply the action matrix. pFinal is the agent's decision, or an ESCALATE copy whose reason
/// starts "downgraded from X: why". pOutcome is APPLIED, SENT_FOR_APPROVAL, RESENT, REJECTED or
/// DOWNGRADED:X. On APPLIED pFixed is the new, saved message. Sends nothing and logs nothing.
/// pUngrounded: the grounding gate's failures in enforce mode; any action but ESCALATE is downgraded.
Method Plan(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pFinal As AgenticProd.Msg.Decision, Output pOutcome As %String, Output pFixed As %Persistent, pUngrounded As %String = "") As %Status
{
	Set (pFinal, pOutcome, pFixed) = ""
	Set tSC = $$$OK
	Try {
		Set tAction = pDecision.Decision, tWhy = ""
		If (pUngrounded '= "") && (tAction '= "ESCALATE") {
			// Before AUTO_FIX builds its copy: an ungrounded fix is never even saved
			Set tWhy = "ungrounded: "_pUngrounded
		} ElseIf tAction = "AUTO_FIX" {
			// The agent read the flagged text, so its fix may be the injected instruction
			Set tWhy = $SELECT(pRequest.Flags.Count(): "suspicious instruction in the message text ("_..FlagRefs(pRequest)_")", 1: ..AutoFixRefusal(pRequest, pDecision, .pFixed))
			Set pOutcome = "APPLIED"
		} ElseIf tAction = "RESEND" {
			If pDecision.ErrorClass '= "TRANSIENT" {
				Set tWhy = "RESEND is only for TRANSIENT errors, not "_pDecision.ErrorClass
			} ElseIf ..ResendCount(pRequest.HeaderId) {
				Set tWhy = "message was already resent once"
			}
			Set pOutcome = "RESENT"
		} ElseIf tAction = "REJECT" {
			If ..#REJECTABLE '[ (","_pDecision.ErrorClass_",") Set tWhy = "REJECT is only for STRUCTURE_ERROR or ROUTING, not "_pDecision.ErrorClass
			Set pOutcome = "REJECTED"
		} Else {
			// MAP_CODE is never applied here: a person approves every new mapping
			Set pOutcome = "SENT_FOR_APPROVAL"
		}
		If tWhy = "" {
			Set pFinal = pDecision
		} Else {
			Set pFinal = pDecision.Escalated("downgraded from "_tAction_": "_tWhy_$SELECT(pDecision.Reason '= "": " (agent: "_pDecision.Reason_")", 1: ""))
			Set pOutcome = "DOWNGRADED:"_tAction
			$$$LOGWARNING("Triage header "_pRequest.HeaderId_" downgraded from "_tAction_": "_tWhy)
		}
		For i = 1:1:pRequest.Flags.Count() Do pFinal.Evidence.Insert("suspicious instruction in "_pRequest.Flags.GetAt(i))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Grounding gate: every claim in pDecision must trace to the message, this agent session's
/// tool results or the LOINC KB. pResult is "" when GroundingStrictness is off, else
/// {strictness, grounded, failed (check names), summary (what failed), checks:[{check, pass,
/// detail}]}. Format-specific checks come from the format's checker (CHECKERS). Acts on nothing.
Method Ground(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pResult As %DynamicObject) As %Status
{
	Set pResult = ""
	Quit:..GroundingStrictness="off" $$$OK
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(pDecision.%JSONExportToString(.tJSON))
		Set tDecision = ##class(%DynamicObject).%FromJSON(tJSON)
		Set tChecks = []
		Do ..SessionResults(pDecision.AgentSessionId, .tToolText, .tSearched)
		Set tKB = ""
		If (tDecision.decision = "MAP_CODE") && $IsObject(tDecision.mapping) {
			Set tLoinc = tDecision.mapping.loinc, tCode = tDecision.mapping."local_code"
			Set tKB = ..KBEntry(tLoinc)
			Do ..AddCheck(tChecks, "loinc_in_kb", $IsObject(tKB), "LOINC "_tLoinc_$SELECT($IsObject(tKB): " is in the KB ("_tKB.system_", "_tKB.units_")", 1: " is not in the LOINC KB"))
			Do ..AddCheck(tChecks, "loinc_from_search", $LISTFIND($LISTFROMSTRING(tSearched), tLoinc) > 0,
				$SELECT(tSearched = "": "no search_loinc result in this agent session", 1: "search_loinc in this session returned "_$TRANSLATE(tSearched, ",", " ")))
			Set tRevoked = ##class(AgenticProd.Data.LearnedMapping).RevokedNote(tCode, tLoinc, ..CodeTable)
			Do ..AddCheck(tChecks, "not_revoked", tRevoked = "", $SELECT(tRevoked = "": "mapping was never revoked", 1: tCode_" -> "_tLoinc_" was revoked by "_tRevoked))
		}
		Set tChecker = ..CheckerFor(pRequest.Format), tMsgText = ""
		If $$$ISOK(##class(AgenticProd.Tools.Base).OpenBody(pRequest.HeaderId, .tBody)) {
			If tChecker '= "" $$$ThrowOnError($CLASSMETHOD(tChecker, "GroundingProblems", tBody, tDecision, tKB, tChecks, ..SearchCandidates(tSearched)))
			Set tMsgText = $SELECT(tBody.%Extends("EnsLib.EDI.Document"): tBody.OutputToString(), 1: "")
			// The agent saw the masked copy, so a quote of a masked value is grounded too
			Set tMasker = ##class(AgenticProd.Tools.Base).MaskerFor($CLASSNAME(tBody))
			If tMasker '= "", $$$ISOK($CLASSMETHOD(tMasker, "MaskedText", tBody, .tMasked)) Set tMsgText = tMsgText_$CHAR(10)_tMasked
		} Else {
			Do ..AddCheck(tChecks, "message", 0, "failed message could not be opened")
		}
		Set tUnverified = ..UnverifiedQuotes(tDecision, tMsgText_$CHAR(10)_pRequest.ErrorText_$CHAR(10)_tToolText)
		Do ..AddCheck(tChecks, "evidence_quotes", tUnverified = "", $SELECT(tUnverified = "": "every quoted value is in the message or a tool result", 1: "unverified quote: "_tUnverified))

		Set (tFailed, tSummary) = "", tIter = tChecks.%GetIterator()
		While tIter.%GetNext(, .tCheck) {
			Continue:tCheck.pass
			Set tFailed = tFailed_$SELECT(tFailed '= "": ",", 1: "")_tCheck.check
			Set tSummary = tSummary_$SELECT(tSummary '= "": "; ", 1: "")_tCheck.check_" ("_tCheck.detail_")"
		}
		Set pResult = {"strictness":(..GroundingStrictness), "failed":(tFailed), "summary":(tSummary), "checks":(tChecks)}
		Do pResult.%Set("grounded", tFailed = "", "boolean")
		$$$TRACE("Grounding header "_pRequest.HeaderId_": "_$SELECT(tFailed = "": "grounded", 1: "failed "_tFailed))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Session ContextData as JSON, "" when it cannot be read. Build 154 sometimes saves a session
/// with its empty first snapshot still in front of the real one ({..}{..}): the last one counts.
ClassMethod SessionContext(pStream As %Stream.Object) As %DynamicObject [ Internal ]
{
	Try {
		Do pStream.Rewind()
		Set tContext = ##class(%DynamicObject).%FromJSON(pStream)
	} Catch {
		Set tContext = ""
	}
	Quit:$IsObject(tContext) tContext
	Try {
		Do pStream.Rewind()
		Set tText = pStream.Read(pStream.Size)
		Set tStart = 0, tAt = 0
		For {
			Set tAt = $FIND(tText, "{""version"":", tAt)
			Quit:'tAt
			Set tStart = tAt - $LENGTH("{""version"":")
		}
		Set:tStart>1 tContext = ##class(%DynamicObject).%FromJSON($EXTRACT(tText, tStart, *))
	} Catch {
		Set tContext = ""
	}
	Quit tContext
}

/// Text of every tool result in AI Hub session pSessionId (masked as the tools return it) and
/// the LOINC codes search_loinc returned, comma separated: from ToolCall.ResultSummary, or from
/// the saved session for calls logged before the summary was kept.
ClassMethod SessionResults(pSessionId As %String, Output pText As %String, Output pSearched As %String) [ Internal ]
{
	Set (pText, pSearched, tFromSession) = ""
	Quit:pSessionId=""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ResultSummary FROM AgenticProd_Data.ToolCall WHERE AgentSessionId = ? AND Namespace = ? AND Tool = 'search_loinc' AND Status = 'OK'", pSessionId, $NAMESPACE)
	While tRS.%Next() {
		Set:tRS.ResultSummary'="" pSearched = pSearched_$SELECT(pSearched '= "": ",", 1: "")_tRS.ResultSummary
	}
	Set tSession = ##class(%AI.Agent.Session).%OpenId(pSessionId)
	Quit:'$IsObject(tSession)
	Set tStream = tSession.ContextData
	Quit:'$IsObject(tStream)
	Set tContext = ..SessionContext(tStream)
	Quit:'$IsObject(tContext)||'$IsObject(tContext.messages)
	Set tIter = tContext.messages.%GetIterator()
	While tIter.%GetNext(, .tMsg) {
		If $IsObject(tMsg."tool_calls") {
			Set tCalls = tMsg."tool_calls".%GetIterator()
			While tCalls.%GetNext(, .tCall) {
				Set:tCall.name="search_loinc" tSearch(tCall.id) = ""
			}
		} ElseIf tMsg.role = "tool" {
			Set pText = pText_$CHAR(10)_tMsg.content
			Set tId = tMsg."tool_call_id"
			If (tId '= "") && $DATA(tSearch(tId)) {
				Set tCodes = ##class(AgenticProd.Data.ToolCall).LoincCodesOf(tMsg.content)
				Set:tCodes'="" tFromSession = tFromSession_$SELECT(tFromSession '= "": ",", 1: "")_tCodes
			}
		}
	}
	Set:pSearched="" pSearched = tFromSession
}

/// {loinc, system, units, display} of pLoinc in the search_loinc KB, "" when it is not there.
ClassMethod KBEntry(pLoinc As %String) As %DynamicObject [ Internal ]
{
	Quit:pLoinc="" ""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 loinc, ""system"" AS Sys, method, units, text FROM "_##class(AgenticProd.Tools.Mapping).#LOINCTABLE_" WHERE loinc = ?", pLoinc)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Quit:'tRS.%Next() ""
	Quit {"loinc":(tRS.loinc), "system":(tRS.Sys), "method":(tRS.method), "units":(tRS.units), "display":($PIECE(tRS.text, " | "))}
}

/// KB rows of the codes search_loinc returned in this session (pSearched, comma list), once each.
/// The format checker uses them to see whether the message singles out one candidate.
ClassMethod SearchCandidates(pSearched As %String) As %DynamicArray [ Internal ]
{
	Set tList = []
	For i = 1:1:$LENGTH(pSearched, ",") {
		Set tCode = $PIECE(pSearched, ",", i)
		Continue:((tCode = "") || $DATA(tSeen(tCode)))
		Set tSeen(tCode) = "", tRow = ..KBEntry(tCode)
		Do:$IsObject(tRow) tList.%Push(tRow)
	}
	Quit tList
}

/// Quoted values ('...' or "...") in pDecision's evidence that appear neither in pSources nor
/// among the decision's own proposed values (fix "to", mapping), as a list; "" when none.
/// Case and runs of spaces are ignored.
ClassMethod UnverifiedQuotes(pDecision As %DynamicObject, pSources As %String) As %String
{
	Quit:'$IsObject(pDecision.evidence) ""
	Set tSources = ..Squeeze(pSources)
	If $IsObject(pDecision.mapping) Set tSources = tSources_" "_..Squeeze(pDecision.mapping.loinc_" "_pDecision.mapping.display_" "_pDecision.mapping."local_code")
	If $IsObject(pDecision.fix) {
		Set tIter = pDecision.fix.%GetIterator()
		While tIter.%GetNext(, .tStep) {
			Set:$IsObject(tStep) tSources = tSources_" "_..Squeeze(tStep.%Get("to"))
		}
	}
	Set tOut = "", tIter = pDecision.evidence.%GetIterator()
	While tIter.%GetNext(, .tLine) {
		// A quote opens after a non-word character, so "doesn't" or "it's" is not one
		Set tMatch = ##class(%Regex.Matcher).%New("(?:^|[^\w])(?:'([^']+)'|""([^""]+)"")(?!\w)", tLine)
		While tMatch.Locate() {
			Set tQuote = tMatch.Group(1)_tMatch.Group(2)
			Continue:$ZSTRIP(tQuote, "<>W")=""
			Continue:tSources[..Squeeze(tQuote)
			Set tOut = tOut_$SELECT(tOut '= "": ", ", 1: "")_"'"_$EXTRACT(tQuote, 1, 80)_"'"
		}
	}
	Quit tOut
}

ClassMethod Squeeze(pText As %String) As %String [ Internal ]
{
	Quit $ZCONVERT($ZSTRIP(pText, "<>=W"), "L")
}

ClassMethod AddCheck(pChecks As %DynamicArray, pName As %String, pPass As %Boolean, pDetail As %String) [ Internal ]
{
	Set tCheck = {"check":(pName), "detail":(pDetail)}
	Do tCheck.%Set("pass", ''pPass, "boolean")
	Do pChecks.%Push(tCheck)
}

/// The reviewer's answer to the ApprovalTask sent for DecisionLog row pCompletionKey.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Quit:'$IsObject(callresponse)
		Quit:'callrequest.%Extends("AgenticProd.Msg.ApprovalTask")
		$$$ThrowOnError(..Review(request, callrequest, callresponse, pCompletionKey, .tFixed, .tResend, .tResendAsIs))
		If request.TraceParent '= "" {
			Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pCompletionKey)
			If $IsObject(tLog) Do ##class(AgenticProd.Telemetry.Trace).ReviewSpan(request.TraceParent, tLog.CreatedAt, callresponse.%Action, tLog.Outcome, callrequest.Decision)
		}
		If $IsObject(tFixed) $$$ThrowOnError(..SendRequestAsync(..FixTarget(request), tFixed, 0))
		If tResend '= "" $$$ThrowOnError(..ResendOriginal(tResend))
		If tResendAsIs '= "" $$$ThrowOnError(##class(Ens.MessageHeader).ResendDuplicatedMessage(tResendAsIs))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Act on pAnswer to pTask and record it on DecisionLog row pLogId (Outcome, Reviewer).
/// EVALACTION on an eval row: Outcome unchanged, nothing done. Reject: REVIEW_REJECTED.
/// MAP_CODE approved: ApplyMapping with the reviewer's Loinc, APPROVED and pResend = the failed
/// header to resend; a bad LOINC is REVIEW_BAD_LOINC, a revoked mapping approved without a Note
/// is REVIEW_REVOKED, nothing written for either.
/// ESCALATE approved: with a fix, CheckFix again; on PASS or PASS_NEEDS_REVIEW pFixed is the
/// new, saved message to send (REVIEW_APPLIED), else REVIEW_FIX_FAILED. Without a fix,
/// REVIEW_CLOSED. RESEND approved (propose mode): pResendAsIs = the header to resend to its own
/// target, REVIEW_RESENT. REJECT approved: written back for the sender, REVIEW_RETURNED.
/// Sends nothing.
Method Review(pRequest As AgenticProd.Msg.TriageRequest, pTask As AgenticProd.Msg.ApprovalTask, pAnswer As EnsLib.Workflow.TaskResponse, pLogId As %String, Output pFixed As %Persistent, Output pResend As %String, Output pResendAsIs As %String) As %Status
{
	Set (pFixed, pResend, pResendAsIs) = ""
	Set tSC = $$$OK
	Try {
		Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pLogId, , .tSC)
		$$$ThrowOnError(tSC)
		Set tLog.Reviewer = pAnswer.%UserName
		Set tLog.ReviewedAt = $ZDATETIME($ZTIMESTAMP, 3)
		If (pAnswer.%Action = ..#EVALACTION) && (tLog.EvalRunId '= "") {
			// Outcome stays as Eval.Runner scored it, so Rescore gives the same result
			Set tLog.Reviewer = "eval", tLog.ReviewNote = "eval task closed by Eval.Runner, not reviewed"
		} ElseIf pAnswer.%Action '= "Approve" {
			Set tLog.Outcome = "REVIEW_REJECTED"
		} ElseIf pTask.Decision = "MAP_CODE" {
			Set tLoinc = $ZSTRIP(pAnswer.%FormValues.GetAt("Loinc"), "<>W")
			Set:tLoinc="" tLoinc = pTask.Loinc
			Set tNote = $ZSTRIP(pAnswer.%FormValues.GetAt("Note"), "<>W")
			Set tRevoked = ##class(AgenticProd.Data.LearnedMapping).RevokedNote(pTask.LocalCode, tLoinc, ..CodeTable)
			If (tRevoked '= "") && (tNote = "") {
				// A revoked memory comes back only with a person's stated reason, never by a click
				Set tLog.Outcome = "REVIEW_REVOKED", tLog.ReviewNote = pTask.LocalCode_" -> "_tLoinc_" was revoked ("_tRevoked_"); approve again with a Note to learn it again"
				$$$LOGWARNING("Reviewer "_pAnswer.%UserName_" approved revoked mapping "_pTask.LocalCode_" -> "_tLoinc_" without a note; not applied")
			} Else {
				$$$ThrowOnError(..ApplyMapping(pTask, tLoinc, .tWhy, pLogId, pAnswer.%UserName, tNote, .tWarning, ..CodeTable, ..CodeTableFormat))
				If tWhy = "" {
					Set tLog.Loinc = tLoinc, tLog.Outcome = "APPROVED", pResend = pRequest.HeaderId
					Set:tWarning'="" tLog.ReviewNote = tWarning
				} Else {
					// The message stays failed; the reviewer can answer a new task, not this one
					Set tLog.Outcome = "REVIEW_BAD_LOINC", tLog.ReviewNote = tWhy
					$$$LOGWARNING("Reviewer "_pAnswer.%UserName_" approved '"_tLoinc_"' for "_pTask.LocalCode_" (header "_pTask.HeaderId_"), not applied: "_tWhy)
				}
			}
		} ElseIf pTask.Decision = "RESEND" {
			// Only a propose-mode task carries RESEND: the approval is the resend
			Set tLog.Outcome = "REVIEW_RESENT", pResendAsIs = pRequest.HeaderId
		} ElseIf pTask.Decision = "REJECT" {
			Set tReturn = ##class(AgenticProd.Msg.Decision).%New()
			Set tReturn.ErrorClass = pTask.ErrorClass, tReturn.Reason = pTask.Reason
			$$$ThrowOnError(..WriteRejected(pRequest, tReturn))
			Set tLog.Outcome = "REVIEW_RETURNED"
		} ElseIf pTask.FixJSON = "" {
			Set tLog.Outcome = "REVIEW_CLOSED"
		} Else {
			// The person stands in for the AUTO_FIX whitelist, not for validation or the identity guard
			Set tWhy = ..RecheckFix(pRequest, ##class(%DynamicArray).%FromJSON(pTask.FixJSON), 1, .pFixed)
			If tWhy = "" {
				Set tLog.Outcome = "REVIEW_APPLIED"
				Set tLog.FixedBodyClass = $CLASSNAME(pFixed), tLog.FixedBodyId = pFixed.%Id()
			} Else {
				Set tLog.Outcome = "REVIEW_FIX_FAILED", tLog.ReviewNote = tWhy
				$$$LOGWARNING("Reviewer "_pAnswer.%UserName_" approved the fix for header "_pTask.HeaderId_", not applied: "_tWhy)
			}
		}
		$$$ThrowOnError(tLog.%Save())
		$$$TRACE("Review of header "_pTask.HeaderId_" by "_pAnswer.%UserName_": "_pAnswer.%Action_", outcome "_tLog.Outcome)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Write pTable pTask.LocalCode -> "pLoinc^display" (pFormat "loinc": the bare code) for an approved MAP_CODE (pLoinc is the
/// reviewer's correction, if any) and its Data.LearnedMapping row (pLogId = the decision's
/// DecisionLog row, pNote = the reviewer's note). pWhy is "" when written, else why not; then
/// nothing is written. Display comes from the LOINC subset; a valid code outside it keeps the
/// agent's display only if the reviewer left the code as proposed, and pWarning records that it
/// was learned without being in the KB.
ClassMethod ApplyMapping(pTask As AgenticProd.Msg.ApprovalTask, pLoinc As %String, Output pWhy As %String, pLogId As %String = "", pReviewer As %String = "", pNote As %String = "", Output pWarning As %String, pTable As %String = {##class(AgenticProd.Tools.Mapping).#CODEMAP}, pFormat As %String = "loinc^display") As %Status
{
	Set (pWhy, pWarning) = ""
	Set tSC = $$$OK
	Try {
		Set pWhy = ..LoincProblem(pLoinc)
		Set:(pWhy="")&&(pTask.LocalCode="") pWhy = "task has no local code"
		Quit:pWhy'=""
		Set tDisplay = ..LoincDisplay(pLoinc, .tFound)
		Set:'tFound tDisplay = $SELECT(pLoinc = pTask.Loinc: pTask.Display, 1: "")
		Set tValue = $SELECT(pFormat = "loinc": pLoinc, 1: pLoinc_"^"_tDisplay)
		$$$ThrowOnError(##class(Ens.Util.LookupTable).%UpdateValue(pTable, pTask.LocalCode, tValue))
		$$$TRACE(pTable_" "_pTask.LocalCode_" -> "_tValue)
		// Grounding of the final code: a reviewer may correct to a code outside the KB, but it is recorded
		Set:'tFound pWarning = "LOINC "_pLoinc_" is not in the LOINC KB; learned on the reviewer's word"
		Set:pNote'="" pWarning = pWarning_$SELECT(pWarning '= "": "; ", 1: "")_"reviewer note: "_pNote
		Set tLog = $SELECT(pLogId '= "": ##class(AgenticProd.Data.DecisionLog).%OpenId(pLogId), 1: "")
		Set tEvidence = ""
		For i = 1:1:pTask.Evidence.Count() Set tEvidence = tEvidence_$SELECT(i > 1: $CHAR(10), 1: "")_pTask.Evidence.GetAt(i)
		$$$ThrowOnError(##class(AgenticProd.Data.LearnedMapping).Approved(pTask.LocalCode, $SELECT($IsObject(tLog): tLog.Source, 1: ""), pLoinc, tDisplay, pLogId, $SELECT($IsObject(tLog): tLog.AgentSessionId, 1: ""), tEvidence, pReviewer, pWarning, , pTable))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// "" when pLoinc is NNNNN-N (1 to 7 digits) with a correct Mod 10 check digit, else why not.
ClassMethod LoincProblem(pLoinc As %String) As %String
{
	// 6-digit codes exist since the 100000 range opened; 7 leaves headroom
	Quit:'$MATCH(pLoinc, "\d{1,7}-\d") "'"_pLoinc_"' is not a LOINC code (NNNNN-N)"
	// LOINC Mod 10 = Luhn on the digits before the dash: double every other digit from the right
	Set tNum = $PIECE(pLoinc, "-"), tSum = 0
	For i = 1:1:$LENGTH(tNum) {
		Set tDigit = $EXTRACT(tNum, $LENGTH(tNum) + 1 - i)
		Set:i#2 tDigit = tDigit * 2
		Set tSum = tSum + (tDigit # 10) + (tDigit \ 10)
	}
	Set tCheck = (10 - (tSum # 10)) # 10
	Quit:tCheck'=$PIECE(pLoinc, "-", 2) "'"_pLoinc_"' has a wrong check digit (expected "_tCheck_")"
	Quit ""
}

/// Long name of pLoinc in the search_loinc subset; pFound is 0 when the code is not in it.
ClassMethod LoincDisplay(pLoinc As %String, Output pFound As %Boolean) As %String
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 text FROM "_##class(AgenticProd.Tools.Mapping).#LOINCTABLE_" WHERE loinc = ?", pLoinc)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Set pFound = tRS.%Next()
	// Row text is "long_name | component | system | scale | method | units" (Setup.BuildLoincKB)
	Quit $SELECT(pFound: $PIECE(tRS.text, " | "), 1: "")
}

/// Resend the failed message under pHeaderId to TargetConfigName (LabRouter; empty: its own
/// target): with the new code table entry it now passes the lookup, so no agent call.
Method ResendOriginal(pHeaderId As %String, Output pNewHeaderId As %String) As %Status
{
	Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(pHeaderId, .pNewHeaderId, ..TargetConfigName)
}

ClassMethod SetOutcome(pLogId As %String, pOutcome As %String) As %Status [ Internal ]
{
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%OpenId(pLogId, , .tSC)
	Quit:'$IsObject(tLog) tSC
	Set tLog.Outcome = pOutcome
	Quit tLog.%Save()
}

/// "" when the AUTO_FIX may go ahead, with pFixed the new, saved, fixed message; else why not.
Method AutoFixRefusal(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pFixed As %Persistent) As %String
{
	Set pFixed = ""
	Quit:pDecision.ErrorClass="IDENTITY_ISSUE" "identity issues are never auto-fixed"
	Quit:$LISTFIND($LISTFROMSTRING(..AutoFixDisabled), pDecision.ErrorClass) "auto-fix disabled in Settings for "_pDecision.ErrorClass
	Quit:'pDecision.Validated "agent did not report a passing validate_fix"
	Quit:pDecision.Confidence<..AutoFixThreshold "confidence "_pDecision.Confidence_" is below AutoFixThreshold "_..AutoFixThreshold
	Quit:pDecision.Fix.Count()=0 "no fix steps"
	Set tChecker = ..CheckerFor(pRequest.Format)
	// "from" is always sent, so a step the agent left without one must match an empty value
	Set tFix = []
	For i = 1:1:pDecision.Fix.Count() {
		Set tStep = pDecision.Fix.GetAt(i)
		Do tFix.%Push({"path":(tStep.Path), "from":(tStep.FromValue), "to":(tStep.ToValue)})
	}
	Quit ..RecheckFix(pRequest, tFix, 0, .pFixed)
}

/// Run the format's CheckFix on pFix ([{path, from, to}]) against the failed message.
/// "" when it may be applied, with pFixed the new, saved message; else why not.
/// pReviewed: a person approved it, so PASS_NEEDS_REVIEW is accepted too.
Method RecheckFix(pRequest As AgenticProd.Msg.TriageRequest, pFix As %DynamicArray, pReviewed As %Boolean, Output pFixed As %Persistent) As %String
{
	Set pFixed = ""
	Set tChecker = ..CheckerFor(pRequest.Format)
	Quit:tChecker="" "no fix checker for format '"_pRequest.Format_"'"
	Set tSC = ##class(AgenticProd.Tools.Base).OpenBody(pRequest.HeaderId, .tBody)
	Quit:$$$ISERR(tSC) "cannot open the failed message: "_$SYSTEM.Status.GetErrorText(tSC)
	Set tSC = $CLASSMETHOD(tChecker, "CheckFix", tBody, pFix, .tResult, .tCopy)
	Quit:$$$ISERR(tSC) "re-check of the fix did not run: "_$SYSTEM.Status.GetErrorText(tSC)
	Quit:tResult.result="REFUSED" "fix touches a protected identity field: "_tResult.errors.%Get(0)
	Quit:(tResult.result="PASS_NEEDS_REVIEW")&&'pReviewed "fix validates but is not auto-fixable: "_$EXTRACT(tResult.errors.%ToJSON(), 1, 500)
	Quit:(tResult.result'="PASS")&&(tResult.result'="PASS_NEEDS_REVIEW") "Triage re-check of the fix did not pass: "_$EXTRACT(tResult.errors.%ToJSON(), 1, 500)
	Set tSC = tCopy.%Save()
	Quit:$$$ISERR(tSC) "cannot save the fixed message: "_$SYSTEM.Status.GetErrorText(tSC)
	Set pFixed = tCopy
	Quit ""
}

/// Carry out pOutcome from Plan. pLogId (DecisionLog row) comes back as the approval's completion key.
Method Dispatch(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pOutcome As %String, pFixed As %Persistent, pLogId As %String = "") As %Status
{
	If $EXTRACT(pOutcome, 1, 9) = "OBSERVED:" {
		$$$LOGINFO("Observe mode: header "_pRequest.HeaderId_" would be "_$EXTRACT(pOutcome, 10, *)_"; nothing sent")
		Quit $$$OK
	}
	If pOutcome = "APPLIED" Quit ..SendRequestAsync(..FixTarget(pRequest), pFixed, 0)
	If pOutcome = "RESENT" Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(pRequest.HeaderId)
	If pOutcome = "REJECTED" {
		$$$LOGWARNING("Triage rejected header "_pRequest.HeaderId_" ("_pDecision.ErrorClass_"): "_pDecision.Reason)
		Quit ..WriteRejected(pRequest, pDecision)
	}
	Quit ..SendRequestAsync(..ApprovalTarget, ##class(AgenticProd.Msg.ApprovalTask).FromDecision(pRequest, pDecision), 1, pLogId)
}

/// TargetConfigName, or when it is empty the target of the failed message itself.
Method FixTarget(pRequest As AgenticProd.Msg.TriageRequest) As %String
{
	Quit:..TargetConfigName'="" ..TargetConfigName
	Set tHeader = ##class(Ens.MessageHeader).%OpenId(pRequest.HeaderId)
	Quit $SELECT($IsObject(tHeader): tHeader.TargetConfigName, 1: "")
}

/// Write the rejected message and a reason file into RejectPath for the sender to pick up:
/// rejected_<headerId>.msg and rejected_<headerId>.reason.txt.
Method WriteRejected(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(AgenticProd.Tools.Base).OpenBody(pRequest.HeaderId, .tBody))
		If '##class(%File).DirectoryExists(..RejectPath) Do ##class(%File).CreateDirectoryChain(..RejectPath)
		Set tBase = ##class(%File).NormalizeFilename("rejected_"_pRequest.HeaderId, ..RejectPath)
		// HL7, X12 and the other EDI documents serialise themselves; other formats get a pointer
		Set tText = $SELECT(tBody.%Extends("EnsLib.EDI.Document"): tBody.OutputToString(), 1: $CLASSNAME(tBody)_" "_tBody.%Id())
		$$$ThrowOnError(..WriteFile(tBase_".msg", tText))
		Set tNL = $CHAR(10)
		Set tReason = "Header: "_pRequest.HeaderId_tNL_"Source: "_pRequest.Source_tNL
			_"Error class: "_pDecision.ErrorClass_tNL_"Reason: "_pDecision.Reason_tNL_"Errors: "_pRequest.ErrorText_tNL
		$$$ThrowOnError(..WriteFile(tBase_".reason.txt", tReason))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod WriteFile(pPath As %String, pText As %String) As %Status [ Internal ]
{
	Set tFile = ##class(%Stream.FileCharacter).%New()
	Set tSC = tFile.LinkToFile(pPath)
	Quit:$$$ISERR(tSC) tSC
	Set tSC = tFile.Write(pText)
	Quit:$$$ISERR(tSC) tSC
	Quit tFile.%Save()
}

/// True if the failed message's body is one Triage built for an APPLIED fix (DecisionLog).
ClassMethod FixedByTriage(pHeaderId As %Integer) As %Boolean
{
	// DecisionLog is shared: body IDs repeat across namespaces
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog d, Ens.MessageHeader h WHERE h.ID = ? AND d.Namespace = ? AND d.FixedBodyId = h.MessageBodyId AND d.FixedBodyClass = h.MessageBodyClassName", pHeaderId, $NAMESPACE)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Do tRS.%Next()
	Quit tRS.N > 0
}

/// RESENT decisions already logged for this message. A resend gets a new header but keeps the
/// body, so headers sharing the body count too.
ClassMethod ResendCount(pHeaderId As %Integer) As %Integer
{
	Set tSQL = "SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog WHERE Outcome = 'RESENT' AND Namespace = ? AND (HeaderId = ? OR HeaderId IN ("
		_"SELECT h.ID FROM Ens.MessageHeader h, Ens.MessageHeader o WHERE o.ID = ? AND h.MessageBodyClassName = o.MessageBodyClassName AND h.MessageBodyId = o.MessageBodyId))"
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, $NAMESPACE, pHeaderId, pHeaderId)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Do tRS.%Next()
	Quit +tRS.N
}

/// "NTE(1):3, OBX(1):5" from the request's InjectionGuard flags.
ClassMethod FlagRefs(pRequest As AgenticProd.Msg.TriageRequest) As %String [ Internal ]
{
	Set tRefs = ""
	For i = 1:1:pRequest.Flags.Count() Set tRefs = tRefs_$SELECT(tRefs '= "": ", ", 1: "")_$PIECE(pRequest.Flags.GetAt(i), ": ")
	Quit tRefs
}

ClassMethod CheckerFor(pFormat As %String) As %String [ Internal ]
{
	For i = 1:1:$LENGTH(..#CHECKERS, ",") {
		Set tPair = $PIECE(..#CHECKERS, ",", i)
		Quit:$PIECE(tPair, "=")=pFormat
		Set tPair = ""
	}
	Quit $PIECE($GET(tPair), "=", 2)
}

Storage Default
{
<Data name="TriageDefaultData">
<Subscript>"Triage"</Subscript>
<Value name="1">
<Value>AgentTarget</Value>
</Value>
<Value name="2">
<Value>AgentTimeout</Value>
</Value>
<Value name="3">
<Value>TargetConfigName</Value>
</Value>
<Value name="4">
<Value>ApprovalTarget</Value>
</Value>
<Value name="5">
<Value>AutoFixThreshold</Value>
</Value>
<Value name="6">
<Value>RejectPath</Value>
</Value>
<Value name="7">
<Value>TracingEnabled</Value>
</Value>
<Value name="8">
<Value>AutoFixDisabled</Value>
</Value>
<Value name="9">
<Value>GroundingStrictness</Value>
</Value>
<Value name="10">
<Value>ActionMode</Value>
</Value>
<Value name="11">
<Value>CodeTable</Value>
</Value>
<Value name="12">
<Value>CodeTableFormat</Value>
</Value>
</Data>
<DefaultData>TriageDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
