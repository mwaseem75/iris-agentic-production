Include (Ensemble, %AI.Errors)

/// Runs AgenticProd.Agent.TriageAgent for one TriageRequest and returns its Decision.
/// Read-only: it only proposes; AgenticProd.Process.Triage acts on the Decision.
/// Every AI Hub session is saved (Decision.AgentSessionId) so it can be replayed without a new call.
/// Callers should wait about 120 s (SendRequestSync timeout): the provider has no timeout setting.
Class AgenticProd.Operation.Agent Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Sent once when the run ends on MaxIterations without a final answer.
Parameter FINALANSWER = "Tool budget used up. Answer now with the decision JSON from what you found, no more tool calls.";

/// Model ID passed to the agent; overrides TriageAgent's MODEL parameter.
Property Model As %String(MAXLEN = 100) [ InitialExpression = "gpt-5-nano" ];

/// Upper bound on agent loop iterations (tool rounds) per message.
Property MaxIterations As %Integer(MAXVAL = 20, MINVAL = 1) [ InitialExpression = 3 ];

/// Prompt + completion tokens allowed per UTC day across all agent runs (from Data.Usage).
/// When used up, messages get ESCALATE without an LLM call. 0 = no limit.
Property DailyTokenBudget As %Integer(MINVAL = 0) [ InitialExpression = 200000 ];

/// IRIS user this job switches to at start (role from AgenticProd.Setup.AgentSecurity).
/// Empty keeps the production's own user (_Ensemble, %All); only for diagnosis.
Property RunAsUser As %String(MAXLEN = 128) [ InitialExpression = "agentic_agent" ];

/// Tool calls allowed per message. Checked after the run (build 154 has no per-iteration
/// hook); above it the decision is forced to ESCALATE. 0 = no limit.
Property MaxToolCalls As %Integer(MINVAL = 0) [ InitialExpression = 8 ];

/// Prompt + completion tokens allowed per message, checked after the run like MaxToolCalls.
/// 0 = no limit.
Property MaxTokensPerMessage As %Integer(MINVAL = 0) [ InitialExpression = 20000 ];

Parameter SETTINGS = "Model:Agent,MaxIterations:Agent,MaxToolCalls:Agent,MaxTokensPerMessage:Agent,DailyTokenBudget:Agent,RunAsUser:Agent";

/// Fail closed: if the switch fails the item does not start, rather than run the agent with %All.
/// The switch lasts for the job's life, so this item must keep its own pool (no shared jobs).
Method OnInit() As %Status
{
	// Needs CREATE TABLE rights, so before the switch; without it only search_loinc fails
	Set tSC = ##class(AgenticProd.Tools.Mapping).Prepare()
	If $$$ISERR(tSC) $$$LOGWARNING("search_loinc not available: "_$SYSTEM.Status.GetErrorText(tSC))
	If ..RunAsUser = "" {
		$$$LOGWARNING("RunAsUser is empty: agent job keeps "_$USERNAME_" ("_$ROLES_")")
		Quit $$$OK
	}
	If '$SYSTEM.Security.Login(..RunAsUser) {
		Quit $$$ERROR($$$GeneralError, "Agent job could not switch to IRIS user "_..RunAsUser_"; run AgenticProd.Setup.AgentSecurity()")
	}
	$$$LOGINFO("Agent job runs as "_$USERNAME_" roles="_$ROLES)
	Quit $$$OK
}

/// Ask the agent for a decision (see Converse for the one retry and AI Hub errors).
/// Writes one Data.Usage row per agent run, failed runs included; budget-skipped messages write none.
Method Triage(pRequest As AgenticProd.Msg.TriageRequest, Output pResponse As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Set tSession = ""
	Set tStart = $ZHOROLOG
	Try {
		// Never drop the message: over budget it still goes to Triage, as ESCALATE
		Set tUsed = ..TokensUsedToday()
		If ..DailyTokenBudget, tUsed >= ..DailyTokenBudget {
			$$$LOGWARNING("Daily token budget used up ("_tUsed_" of "_..DailyTokenBudget_"), escalating header "_pRequest.HeaderId_" without an LLM call")
			Set pResponse = ..EscalateDecision(pRequest, "Daily token budget used up ("_tUsed_" of "_..DailyTokenBudget_" tokens); agent not called")
			Quit
		}

		Set tAgent = ##class(AgenticProd.Agent.TriageAgent).%New()
		Set tAgent.Model = ..Model
		Set tAgent.MaxIterations = ..MaxIterations
		$$$ThrowOnError(tAgent.%Init())
		Set tSession = tAgent.CreateSession({"cache":{"enabled":1,"cache_system_prompt":1,"cache_tool_definitions":1}})
		// Saved early so ToolCall rows carry the session ID
		$$$ThrowOnError(tSession.%Save())
		Set tAudit = ##class(AgenticProd.Policy.Audit).%New()
		Set tAudit.HeaderId = pRequest.HeaderId
		Set tAudit.AgentSessionId = tSession.%Id()
		$$$ThrowOnError(tAgent.ToolManager.SetAuthPolicy(##class(AgenticProd.Policy.ReadOnly).%New()))
		$$$ThrowOnError(tAgent.ToolManager.SetAuditPolicy(tAudit))

		$$$TRACE("Agent call: model="_..Model_" maxIterations="_..MaxIterations_" headerId="_pRequest.HeaderId)
		Set pResponse = ..Converse(tAgent, tSession, pRequest)

		// Also after an AI Hub error: the tokens were spent and the session is the evidence
		$$$ThrowOnError(tSession.%Save())
		Set tStats = tSession.GetStats()
		Set pResponse = ..ApplyMessageBudget(pRequest, tStats, ..MaxToolCalls, ..MaxTokensPerMessage, pResponse)
		Set pResponse.Model = ..Model
		Set pResponse.PromptTokens = tStats."total_prompt_tokens"
		Set pResponse.CompletionTokens = tStats."total_completion_tokens"
		Set pResponse.AgentSessionId = tSession.%Id()
		Set tUsage = ##class(AgenticProd.Data.Usage).FromStats(tStats, ##class(AgenticProd.Agent.TriageAgent).#PROVIDER, ..Model)
		Set tUsage.HeaderId = pRequest.HeaderId
		Set tUsage.SessionId = pRequest.SessionId
		Set tUsage.AgentSessionId = pResponse.AgentSessionId
		Set tUsage.TotalMs = ($ZHOROLOG - tStart) * 1000 \ 1
		Set tUsage.Decision = pResponse.Decision
		Set tUsage.Confidence = pResponse.Confidence
		$$$ThrowOnError(tUsage.%Save())
		Set pResponse.CostUsd = tUsage.CostUsd
		$$$TRACE("Agent decision="_pResponse.Decision_" session="_pResponse.AgentSessionId_" tokens="_pResponse.PromptTokens_"+"_pResponse.CompletionTokens_" toolCalls="_tStats."total_tool_calls"_" llmMs="_tStats."total_llm_duration_ms")
	} Catch ex {
		Set tSC = ex.AsStatus()
		// Keep the failed conversation for diagnosis.
		If $IsObject(tSession) Do tSession.%Save()
	}
	Quit tSC
}

/// Ask for a decision and parse it. One retry in all: the contract retry, or, when the run ends
/// on MaxIterations, one last turn asking for the answer without tools. An AI Hub error never
/// escapes; it becomes an ESCALATE that names it, so the caller still saves the session and Usage.
Method Converse(pAgent As %AI.Agent, pSession As %AI.Agent.Session, pRequest As AgenticProd.Msg.TriageRequest) As AgenticProd.Msg.Decision
{
	Set tText = ..Ask(pAgent, pSession, ..BuildTask(pRequest), .tError)
	If tError [ $$$AICoreMaxIterationsReached {
		$$$LOGWARNING("Agent used its tool budget without answering, asking once for the final answer")
		Set tText = ..Ask(pAgent, pSession, ..#FINALANSWER, .tError)
		Quit:tError'="" ..EscalateDecision(pRequest, "agent gave no decision after its tool budget: "_tError)
		Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
		Quit:$$$ISERR(tSC) ..EscalateDecision(pRequest, "agent reply after its tool budget broke the decision contract: "_$SYSTEM.Status.GetErrorText(tSC))
		Quit ..MarkNoEvidence(tDecision)
	}
	Quit:tError'="" ..EscalateDecision(pRequest, "agent call failed: "_tError)

	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Set:$$$ISOK(tSC) tSC = ..EvidenceCheck(tDecision)
	Quit:$$$ISOK(tSC) tDecision
	Set tContract = $SYSTEM.Status.GetErrorText(tSC)
	$$$LOGWARNING("Agent reply broke the decision contract, retrying once: "_tContract)
	Set tText = ..Ask(pAgent, pSession, "Your answer was rejected: "_tContract_". Reply again with the decision JSON object only.", .tError)
	Quit:tError'="" ..EscalateDecision(pRequest, "agent call failed on the contract retry: "_tError)
	Set tSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision)
	Quit:$$$ISOK(tSC) ..MarkNoEvidence(tDecision)
	$$$LOGWARNING("Agent reply broke the decision contract twice, escalating: "_$SYSTEM.Status.GetErrorText(tSC))
	Quit ..EscalateDecision(pRequest, "Agent reply broke the decision contract twice: "_$SYSTEM.Status.GetErrorText(tSC))
}

/// MAP_CODE and AUTO_FIX need evidence. Not a contract rule in Decision.Validate: after the
/// retry the decision is kept (see MarkNoEvidence), since Triage and the reviewer still decide.
ClassMethod EvidenceCheck(pDecision As AgenticProd.Msg.Decision) As %Status
{
	If (",MAP_CODE,AUTO_FIX," '[ (","_pDecision.Decision_",")) || pDecision.Evidence.Count() Quit $$$OK
	Quit ##class(AgenticProd.Msg.Decision).ContractError("evidence is required for "_pDecision.Decision)
}

/// pDecision, with evidence "agent gave no evidence" when EvidenceCheck still fails.
ClassMethod MarkNoEvidence(pDecision As AgenticProd.Msg.Decision) As AgenticProd.Msg.Decision
{
	Do:$$$ISERR(..EvidenceCheck(pDecision)) pDecision.Evidence.Insert("agent gave no evidence")
	Quit pDecision
}

/// One agent turn. Returns the reply text, or "" with pError set when AI Hub throws.
Method Ask(pAgent As %AI.Agent, pSession As %AI.Agent.Session, pText As %String, Output pError As %String) As %String
{
	Set pError = "", tText = ""
	Try {
		Set tText = ..AgentChat(pAgent, pSession, pText).Content
	} Catch ex {
		Set pError = ex.DisplayString()
		$$$LOGWARNING("Agent call failed: "_pError)
	}
	Quit tText
}

/// The only place that calls the LLM; unit tests override it with a stub.
Method AgentChat(pAgent As %AI.Agent, pSession As %AI.Agent.Session, pText As %String) As %RegisteredObject
{
	Quit pAgent.Chat(pSession, pText)
}

/// The task text sent to the agent. Error text comes from the interface, so it goes
/// inside an untrusted_data block.
ClassMethod BuildTask(pRequest As AgenticProd.Msg.TriageRequest) As %String
{
	Set tNL = $CHAR(10)
	Quit "Triage this failed message."_tNL
		_"Header ID: "_pRequest.HeaderId_tNL
		_"Session ID: "_pRequest.SessionId_tNL
		_"Source: "_pRequest.Source_tNL
		_"Format: "_pRequest.Format_tNL
		_"Router's first guess at error_class: "_pRequest.ErrorClass_tNL
		_"<untrusted_data source=""error_text"">"_tNL
		_pRequest.ErrorText_tNL
		_"</untrusted_data>"
}

/// Prompt + completion tokens recorded in Data.Usage since 00:00 UTC today.
/// CreatedAt is UTC ($ZTIMESTAMP), so the budget day is a UTC day.
ClassMethod TokensUsedToday() As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT SUM(PromptTokens) + SUM(CompletionTokens) AS Used FROM AgenticProd_Data.Usage WHERE CreatedAt >= ?", $ZDATE($PIECE($ZTIMESTAMP, ","), 3)_" 00:00:00")
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Do tRS.%Next()
	Quit +tRS.Used
}

/// Return pDecision, or an ESCALATE decision when the run's stats (session.GetStats()) are
/// over the per-message tool call or token limit. A limit of 0 is off. The escalated copy keeps
/// the agent's fix, mapping and evidence.
ClassMethod ApplyMessageBudget(pRequest As AgenticProd.Msg.TriageRequest, pStats As %DynamicObject, pMaxToolCalls As %Integer, pMaxTokens As %Integer, pDecision As AgenticProd.Msg.Decision) As AgenticProd.Msg.Decision
{
	Set tToolCalls = +pStats."total_tool_calls"
	Set tTokens = pStats."total_prompt_tokens" + pStats."total_completion_tokens"
	Set tWhy = ""
	If pMaxToolCalls, tToolCalls > pMaxToolCalls Set tWhy = tToolCalls_" tool calls (limit "_pMaxToolCalls_")"
	If pMaxTokens, tTokens > pMaxTokens Set tWhy = tWhy_$SELECT(tWhy '= "": ", ", 1: "")_tTokens_" tokens (limit "_pMaxTokens_")"
	Quit:tWhy="" pDecision
	// The answer may look fine, but a run that needed this much is not trusted for AUTO_FIX
	$$$LOGWARNING("Per-message budget exceeded for header "_pRequest.HeaderId_": "_tWhy_"; agent answered "_pDecision.Decision_", escalating")
	Quit pDecision.Escalated("budget exceeded: "_tWhy_"; agent answered "_pDecision.Decision)
}

/// ESCALATE decision used when the agent gives no valid answer.
ClassMethod EscalateDecision(pRequest As AgenticProd.Msg.TriageRequest, pReason As %String) As AgenticProd.Msg.Decision
{
	Set tDecision = ##class(AgenticProd.Msg.Decision).%New()
	Set tDecision.Decision = "ESCALATE"
	Set tDecision.ErrorClass = $SELECT(pRequest.ErrorClass '= "": pRequest.ErrorClass, 1: "OTHER")
	Set tDecision.Confidence = 0
	Set tDecision.Validated = 0
	Set tDecision.Reason = pReason
	Quit tDecision
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="AgenticProd.Msg.TriageRequest">
    <Method>Triage</Method>
  </MapItem>
</MapItems>
}

}
