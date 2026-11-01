/// Generic question for a hosted agent (Operation.Agent with any AgentClass). Use it from your own
/// process or a routing rule; TriageRequest stays the failed-message request of the Triage process.
Class AgenticProd.Msg.AgentRequest Extends (Ens.Request, %JSON.Adaptor)
{

/// Ens.MessageHeader ID of the message the agent should look at; 0 when the question stands alone.
Property HeaderId As %Integer(%JSONFIELDNAME = "header_id");

/// What to answer. Goes to the model inside an untrusted_data block.
Property Question As %String(%JSONFIELDNAME = "question", MAXLEN = "") [ Required ];

}
