/// Operation.Agent that records the task text it would send and answers "ok", for AgentRequestTest.
Class AgenticProd.Test.Operation.CaptureOp Extends AgenticProd.Operation.Agent
{

Property LastTask As %String(MAXLEN = "");

Method LLMBlocked() As %String
{
	Quit ""
}

Method AgentChat(pAgent As %AI.Agent, pSession As %AI.Agent.Session, pText As %String) As %RegisteredObject
{
	Set ..LastTask = pText
	Quit {"Content":"ok"}
}

}
