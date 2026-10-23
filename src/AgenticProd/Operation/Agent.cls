Include Ensemble

/// Runs AgenticProd.Agent.TriageAgent for one TriageRequest and returns its Decision.
/// Read-only: it only proposes; AgenticProd.Process.Triage acts on the Decision.
/// Every AI Hub session is saved (Decision.AgentSessionId) so it can be replayed without a new call.
/// Callers should wait about 120 s (SendRequestSync timeout): the provider has no timeout setting.
Class AgenticProd.Operation.Agent Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Model ID passed to the agent; overrides TriageAgent's MODEL parameter.
Property Model As %String(MAXLEN = 100) [ InitialExpression = "gpt-5-nano" ];

/// Upper bound on agent loop iterations (tool rounds) per message.
Property MaxIterations As %Integer(MAXVAL = 20, MINVAL = 1) [ InitialExpression = 3 ];

Parameter SETTINGS = "Model:Agent,MaxIterations:Agent";

/// Ask the agent for a decision. If its reply breaks the decision contract, send it the
/// error once; if the second reply also fails, return an ESCALATE decision.
Method Triage(pRequest As AgenticProd.Msg.TriageRequest, Output pResponse As AgenticProd.Msg.Decision) As %Status
{
	Set tSC = $$$OK
	Set tSession = ""
	Try {
		Set tAgent = ##class(AgenticProd.Agent.TriageAgent).%New()
		Set tAgent.Model = ..Model
		Set tAgent.MaxIterations = ..MaxIterations
		$$$ThrowOnError(tAgent.%Init())
		Set tSession = tAgent.CreateSession({"cache":{"enabled":1,"cache_system_prompt":1,"cache_tool_definitions":1}})

		$$$TRACE("Agent call: model="_..Model_" maxIterations="_..MaxIterations_" headerId="_pRequest.HeaderId)
		Set tReply = tAgent.Chat(tSession, ..BuildTask(pRequest))
		Set tParseSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tReply.Content, .pResponse)
		If $$$ISERR(tParseSC) {
			Set tError = $SYSTEM.Status.GetErrorText(tParseSC)
			$$$LOGWARNING("Agent reply broke the decision contract, retrying once: "_tError)
			Set tReply = tAgent.Chat(tSession, "Your answer was rejected: "_tError_". Reply again with the decision JSON object only.")
			Set tParseSC = ##class(AgenticProd.Msg.Decision).FromAgentText(tReply.Content, .pResponse)
			If $$$ISERR(tParseSC) {
				Set tError = $SYSTEM.Status.GetErrorText(tParseSC)
				$$$LOGWARNING("Agent reply broke the decision contract twice, escalating: "_tError)
				Set pResponse = ..EscalateDecision(pRequest, "Agent reply broke the decision contract twice: "_tError)
			}
		}

		$$$ThrowOnError(tSession.%Save())
		Set tStats = tSession.GetStats()
		Set pResponse.Model = ..Model
		Set pResponse.PromptTokens = tStats."total_prompt_tokens"
		Set pResponse.CompletionTokens = tStats."total_completion_tokens"
		Set pResponse.AgentSessionId = tSession.%Id()
		$$$TRACE("Agent decision="_pResponse.Decision_" session="_pResponse.AgentSessionId_" tokens="_pResponse.PromptTokens_"+"_pResponse.CompletionTokens_" toolCalls="_tStats."total_tool_calls"_" llmMs="_tStats."total_llm_duration_ms")
	} Catch ex {
		Set tSC = ex.AsStatus()
		// Keep the failed conversation for diagnosis.
		If $IsObject(tSession) Do tSession.%Save()
	}
	Quit tSC
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
