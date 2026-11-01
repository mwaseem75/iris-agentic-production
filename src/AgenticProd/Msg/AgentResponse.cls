/// The agent's answer to an AgentRequest. A proposal only: the caller decides what to apply.
Class AgenticProd.Msg.AgentResponse Extends (Ens.Response, %JSON.Adaptor)
{

/// Decision word when the reply follows the decision contract (RESEND, ESCALATE, ...); ANSWER
/// for a plain text reply; ESCALATE when the agent was not called or failed.
Property Decision As %String(%JSONFIELDNAME = "decision", MAXLEN = 20);

Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", SCALE = 4);

Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 2000);

/// The agent's reply as written.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// AI Hub session ID, for replay.
Property AgentSessionId As %String(%JSONFIELDNAME = "agent_session_id", MAXLEN = 50);

}
