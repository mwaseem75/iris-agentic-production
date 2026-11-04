/// Operation.Agent with a scripted agent for unit tests: AgentChat answers or throws the next
/// scripted reply and never calls the LLM. The real TriageAgent and session are still built.
Class AgenticProd.Test.Operation.StubAgentOp Extends AgenticProd.Operation.Agent
{

/// Replies in call order; "THROW:<text>" throws an error with that text instead of answering.
Property Script As list Of %String(MAXLEN = "");

Property Calls As %Integer [ InitialExpression = 0 ];

/// Scripted replies are not live calls, so the test-run block does not apply.
Method LLMBlocked() As %String
{
	Quit ""
}

/// 1 to script the no-key path; by default the stub has a key, as the real item does in the tests.
Property KeyMissing As %Boolean [ InitialExpression = 0 ];

Method NoApiKey() As %Boolean
{
	Quit ..KeyMissing
}

Method AgentChat(pAgent As %AI.Agent, pSession As %AI.Agent.Session, pText As %String) As %RegisteredObject
{
	Set ..Calls = ..Calls + 1
	Set tReply = ..Script.GetAt(..Calls)
	If $EXTRACT(tReply, 1, 6) = "THROW:" $$$ThrowStatus($$$ERROR($$$GeneralError, $EXTRACT(tReply, 7, *)))
	Quit {"Content":(tReply)}
}

}
