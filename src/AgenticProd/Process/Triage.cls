Include Ensemble

/// Acts on the triage agent's Decision for one failed message; the only component that does.
/// The agent only proposes: whatever the action matrix does not allow becomes ESCALATE, and an
/// AUTO_FIX is re-checked here, never taken on the agent's word. The original body is never changed.
/// Format-neutral: fixes are re-checked by the format class named in CHECKERS.
Class AgenticProd.Process.Triage Extends Ens.BusinessProcess
{

/// TriageRequest.Format = class with ClassMethod CheckFix(body, fixArray, .result, .fixedCopy),
/// see Tools.HL7.CheckFix.
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

/// Where the new, fixed message goes after an AUTO_FIX.
Property TargetConfigName As Ens.DataType.ConfigName;

/// Workflow operation (role) that gets an ApprovalTask for every MAP_CODE and ESCALATE.
Property ApprovalTarget As Ens.DataType.ConfigName;

/// Lowest agent confidence accepted for AUTO_FIX.
Property AutoFixThreshold As %Numeric(MAXVAL = 1, MINVAL = 0) [ InitialExpression = 0.85 ];

/// Folder for rejected messages and their reason files.
Property RejectPath As %String(MAXLEN = 500) [ InitialExpression = "/home/irisowner/dev/data/rejected/" ];

Parameter SETTINGS = "AgentTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ApprovalTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},AutoFixThreshold:Triage,AgentTimeout:Triage,RejectPath:Triage";

/// Ask the agent, apply the action matrix, act, and log what was done in Data.DecisionLog.
/// pResponse is the decision Triage acted on (the agent's, or its ESCALATE downgrade).
Method OnRequest(pRequest As AgenticProd.Msg.TriageRequest, Output pResponse As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tDecision = ""
		If ..FixedByTriage(pRequest.HeaderId) {
			// Our own fix failed again: another agent round could loop, so a person decides
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "message built by a Triage AUTO_FIX failed again; agent not called a second time")
		} Else {
			Set tSC = ..SendRequestSync(..AgentTarget, pRequest, .tDecision, ..AgentTimeout)
		}
		If $$$ISERR(tSC) || '$IsObject(tDecision) {
			// No answer still ends with a person looking at the message, never a drop
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "agent gave no decision: "_$SELECT($$$ISERR(tSC): $SYSTEM.Status.GetErrorText(tSC), 1: "timed out after "_..AgentTimeout_" s"))
			Set tSC = $$$OK
		}
		$$$ThrowOnError(..Plan(pRequest, tDecision, .pResponse, .tOutcome, .tFixed))
		// Logged before the send: the row ID is the approval task's completion key
		$$$ThrowOnError(##class(AgenticProd.Data.DecisionLog).Record(pRequest, pResponse, .tLogId, tOutcome, $SELECT(tOutcome = "APPLIED": tFixed, 1: "")))
		Set tSendSC = ..Dispatch(pRequest, pResponse, tOutcome, tFixed, tLogId)
		If $$$ISERR(tSendSC) $$$ThrowOnError(..SetOutcome(tLogId, "ERROR:"_tOutcome))
		$$$TRACE("Triage header "_pRequest.HeaderId_": agent "_tDecision.Decision_", outcome "_tOutcome)
		$$$ThrowOnError(tSendSC)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Apply the action matrix. pFinal is the agent's decision, or an ESCALATE copy whose reason
/// starts "downgraded from X: why". pOutcome is APPLIED, SENT_FOR_APPROVAL, RESENT, REJECTED or
/// DOWNGRADED:X. On APPLIED pFixed is the new, saved message. Sends nothing and logs nothing.
Method Plan(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, Output pFinal As AgenticProd.Msg.Decision, Output pOutcome As %String, Output pFixed As %Persistent) As %Status
{
	Set (pFinal, pOutcome, pFixed) = ""
	Set tSC = $$$OK
	Try {
		Set tAction = pDecision.Decision, tWhy = ""
		If tAction = "AUTO_FIX" {
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

/// The reviewer's answer to the ApprovalTask sent for DecisionLog row pCompletionKey.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Quit:'$IsObject(callresponse)
		Quit:'callrequest.%Extends("AgenticProd.Msg.ApprovalTask")
		$$$ThrowOnError(..Review(request, callrequest, callresponse, pCompletionKey, .tFixed, .tResend))
		If $IsObject(tFixed) $$$ThrowOnError(..SendRequestAsync(..TargetConfigName, tFixed, 0))
		If tResend '= "" $$$ThrowOnError(..ResendOriginal(tResend))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Act on pAnswer to pTask and record it on DecisionLog row pLogId (Outcome, Reviewer).
/// EVALACTION on an eval row: Outcome unchanged, nothing done. Reject: REVIEW_REJECTED.
/// MAP_CODE approved: ApplyMapping with the reviewer's Loinc, APPROVED and pResend = the failed
/// header to resend; a bad LOINC is REVIEW_BAD_LOINC, nothing written.
/// ESCALATE approved: with a fix, CheckFix again; on PASS or PASS_NEEDS_REVIEW pFixed is the
/// new, saved message to send (REVIEW_APPLIED), else REVIEW_FIX_FAILED. Without a fix,
/// REVIEW_CLOSED. Sends nothing.
Method Review(pRequest As AgenticProd.Msg.TriageRequest, pTask As AgenticProd.Msg.ApprovalTask, pAnswer As EnsLib.Workflow.TaskResponse, pLogId As %String, Output pFixed As %Persistent, Output pResend As %String) As %Status
{
	Set (pFixed, pResend) = ""
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
			$$$ThrowOnError(..ApplyMapping(pTask, tLoinc, .tWhy))
			If tWhy = "" {
				Set tLog.Loinc = tLoinc, tLog.Outcome = "APPROVED", pResend = pRequest.HeaderId
			} Else {
				// The message stays failed; the reviewer can answer a new task, not this one
				Set tLog.Outcome = "REVIEW_BAD_LOINC", tLog.ReviewNote = tWhy
				$$$LOGWARNING("Reviewer "_pAnswer.%UserName_" approved '"_tLoinc_"' for "_pTask.LocalCode_" (header "_pTask.HeaderId_"), not applied: "_tWhy)
			}
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

/// Write LabCodeMap pTask.LocalCode -> "pLoinc^display" for an approved MAP_CODE (pLoinc is the
/// reviewer's correction, if any). pWhy is "" when written, else why not; then nothing is written.
/// Display comes from the LOINC subset; a valid code outside it keeps the agent's display only
/// if the reviewer left the code as proposed.
ClassMethod ApplyMapping(pTask As AgenticProd.Msg.ApprovalTask, pLoinc As %String, Output pWhy As %String) As %Status
{
	Set pWhy = ""
	Set tSC = $$$OK
	Try {
		Set pWhy = ..LoincProblem(pLoinc)
		Set:(pWhy="")&&(pTask.LocalCode="") pWhy = "task has no local code"
		Quit:pWhy'=""
		Set tDisplay = ..LoincDisplay(pLoinc, .tFound)
		Set:'tFound tDisplay = $SELECT(pLoinc = pTask.Loinc: pTask.Display, 1: "")
		$$$ThrowOnError(##class(Ens.Util.LookupTable).%UpdateValue(##class(AgenticProd.Tools.Mapping).#CODEMAP, pTask.LocalCode, pLoinc_"^"_tDisplay))
		$$$TRACE("LabCodeMap "_pTask.LocalCode_" -> "_pLoinc_"^"_tDisplay)
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

/// Resend the failed message under pHeaderId to TargetConfigName (LabRouter): with the new
/// LabCodeMap entry it now passes the lookup, so no agent call.
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
	If pOutcome = "APPLIED" Quit ..SendRequestAsync(..TargetConfigName, pFixed, 0)
	If pOutcome = "RESENT" Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(pRequest.HeaderId)
	If pOutcome = "REJECTED" {
		$$$LOGWARNING("Triage rejected header "_pRequest.HeaderId_" ("_pDecision.ErrorClass_"): "_pDecision.Reason)
		Quit ..WriteRejected(pRequest, pDecision)
	}
	Quit ..SendRequestAsync(..ApprovalTarget, ##class(AgenticProd.Msg.ApprovalTask).FromDecision(pRequest, pDecision), 1, pLogId)
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
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog d, Ens.MessageHeader h WHERE h.ID = ? AND d.FixedBodyId = h.MessageBodyId AND d.FixedBodyClass = h.MessageBodyClassName", pHeaderId)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Do tRS.%Next()
	Quit tRS.N > 0
}

/// RESENT decisions already logged for this message. A resend gets a new header but keeps the
/// body, so headers sharing the body count too.
ClassMethod ResendCount(pHeaderId As %Integer) As %Integer
{
	Set tSQL = "SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog WHERE Outcome = 'RESENT' AND (HeaderId = ? OR HeaderId IN ("
		_"SELECT h.ID FROM Ens.MessageHeader h, Ens.MessageHeader o WHERE o.ID = ? AND h.MessageBodyClassName = o.MessageBodyClassName AND h.MessageBodyId = o.MessageBodyId))"
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pHeaderId, pHeaderId)
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
</Data>
<DefaultData>TriageDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
