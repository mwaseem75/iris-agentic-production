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

/// Agent operation that answers a TriageRequest with a Decision.
Property AgentTarget As Ens.DataType.ConfigName [ InitialExpression = "AgenticProd.Operation.Agent" ];

/// Seconds to wait for the agent; the provider has no timeout of its own.
Property AgentTimeout As %Integer(MINVAL = 1) [ InitialExpression = 120 ];

/// Where the new, fixed message goes after an AUTO_FIX.
Property TargetConfigName As Ens.DataType.ConfigName;

/// Where MAP_CODE and ESCALATE decisions go for a person to decide (Workflow task from 4.4).
Property ApprovalTarget As Ens.DataType.ConfigName;

/// Lowest agent confidence accepted for AUTO_FIX.
Property AutoFixThreshold As %Numeric(MAXVAL = 1, MINVAL = 0) [ InitialExpression = 0.85 ];

Parameter SETTINGS = "AgentTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ApprovalTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},AutoFixThreshold:Triage,AgentTimeout:Triage";

/// Ask the agent, apply the action matrix, act, and log what was done in Data.DecisionLog.
/// pResponse is the decision Triage acted on (the agent's, or its ESCALATE downgrade).
Method OnRequest(pRequest As AgenticProd.Msg.TriageRequest, Output pResponse As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tDecision = ""
		Set tSC = ..SendRequestSync(..AgentTarget, pRequest, .tDecision, ..AgentTimeout)
		If $$$ISERR(tSC) || '$IsObject(tDecision) {
			// No answer still ends with a person looking at the message, never a drop
			Set tDecision = ##class(AgenticProd.Operation.Agent).EscalateDecision(pRequest, "agent gave no decision: "_$SELECT($$$ISERR(tSC): $SYSTEM.Status.GetErrorText(tSC), 1: "timed out after "_..AgentTimeout_" s"))
			Set tSC = $$$OK
		}
		$$$ThrowOnError(..Plan(pRequest, tDecision, .pResponse, .tOutcome, .tFixed))
		Set tSendSC = ..Dispatch(pRequest, pResponse, tOutcome, tFixed)
		If $$$ISERR(tSendSC) Set tOutcome = "ERROR:"_tOutcome
		$$$ThrowOnError(##class(AgenticProd.Data.DecisionLog).Record(pRequest, pResponse, , tOutcome))
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
			Set tWhy = ..AutoFixRefusal(pRequest, pDecision, .pFixed)
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
			Quit
		}
		Set pFinal = pDecision.Escalated("downgraded from "_tAction_": "_tWhy_$SELECT(pDecision.Reason '= "": " (agent: "_pDecision.Reason_")", 1: ""))
		Set pOutcome = "DOWNGRADED:"_tAction
		$$$LOGWARNING("Triage header "_pRequest.HeaderId_" downgraded from "_tAction_": "_tWhy)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
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
	Quit:tChecker="" "no fix checker for format '"_pRequest.Format_"'"
	Set tSC = ##class(AgenticProd.Tools.Base).OpenBody(pRequest.HeaderId, .tBody)
	Quit:$$$ISERR(tSC) "cannot open the failed message: "_$SYSTEM.Status.GetErrorText(tSC)

	// "from" is always sent, so a step the agent left without one must match an empty value
	Set tFix = []
	For i = 1:1:pDecision.Fix.Count() {
		Set tStep = pDecision.Fix.GetAt(i)
		Do tFix.%Push({"path":(tStep.Path), "from":(tStep.FromValue), "to":(tStep.ToValue)})
	}
	Set tSC = $CLASSMETHOD(tChecker, "CheckFix", tBody, tFix, .tResult, .tCopy)
	Quit:$$$ISERR(tSC) "re-check of the fix did not run: "_$SYSTEM.Status.GetErrorText(tSC)
	Quit:tResult.result="REFUSED" "fix touches a protected identity field: "_tResult.errors.%Get(0)
	Quit:tResult.result'="PASS" "Triage re-check of the fix did not pass: "_$EXTRACT(tResult.errors.%ToJSON(), 1, 500)
	Set tSC = tCopy.%Save()
	Quit:$$$ISERR(tSC) "cannot save the fixed message: "_$SYSTEM.Status.GetErrorText(tSC)
	Set pFixed = tCopy
	Quit ""
}

/// Carry out pOutcome from Plan.
Method Dispatch(pRequest As AgenticProd.Msg.TriageRequest, pDecision As AgenticProd.Msg.Decision, pOutcome As %String, pFixed As %Persistent) As %Status
{
	If pOutcome = "APPLIED" Quit ..SendRequestAsync(..TargetConfigName, pFixed, 0)
	If pOutcome = "RESENT" Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(pRequest.HeaderId)
	If pOutcome = "REJECTED" {
		// TODO 3.8: NACK to the sender once Service.LabFile exists
		$$$LOGWARNING("Triage rejected header "_pRequest.HeaderId_" ("_pDecision.ErrorClass_"): "_pDecision.Reason)
		Quit $$$OK
	}
	Quit ..SendRequestAsync(..ApprovalTarget, pDecision, 0)
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
</Data>
<DefaultData>TriageDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
