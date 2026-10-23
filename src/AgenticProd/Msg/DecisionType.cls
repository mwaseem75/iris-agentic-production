/// Decision values allowed in the agent's decision contract.
Class AgenticProd.Msg.DecisionType Extends %String [ ClassType = datatype ]
{

Parameter MAXLEN = 20;

Parameter VALUELIST = ",AUTO_FIX,MAP_CODE,RESEND,REJECT,ESCALATE";

}
