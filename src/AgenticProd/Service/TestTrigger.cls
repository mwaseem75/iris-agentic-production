/// Sends one synthetic TriageRequest to the agent operation so the run shows in Visual Trace.
/// Phase 1 only; replaced by Service.LabFile and Demo in phases 3 and 4.
///   do ##class(AgenticProd.Service.TestTrigger).Send(.sessionId)
Class AgenticProd.Service.TestTrigger Extends Ens.BusinessService
{

/// Config item that receives the request.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "TriageAgent" ];

/// Seconds to wait for the agent's decision.
Property ResponseTimeout As %Integer(MINVAL = 1) [ InitialExpression = 120 ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ResponseTimeout:Basic";

/// pInput is a TriageRequest; pOutput is the Decision.
Method OnProcessInput(pInput As AgenticProd.Msg.TriageRequest, Output pOutput As AgenticProd.Msg.Decision) As %Status
{
	Quit ..SendRequestSync(..TargetConfigName, pInput, .pOutput, ..ResponseTimeout)
}

/// Push one synthetic request through the running production (config item "TestTrigger").
/// Calls the LLM once (twice if the first reply breaks the contract).
/// pSessionId returns the Visual Trace session ID.
ClassMethod Send(Output pSessionId As %Integer, Output pDecision As AgenticProd.Msg.Decision) As %Status
{
	Set pSessionId = "", pDecision = ""
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(Ens.Director).CreateBusinessService("TestTrigger", .tService))
		Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
		// Synthetic header ID: the phase 1 GetErrorEvents tool is a stub and ignores it.
		Set tRequest.HeaderId = 900001
		Set tRequest.Source = "LAB_SIM"
		Set tRequest.Format = "HL7v2"
		Set tRequest.ErrorClass = "BAD_FORMAT"
		Set tRequest.ErrorText = "ORU^R01 OBX(1):14 value '2026-10-23 10:15' is not a valid HL7 TS"
		Set tSC = tService.ProcessInput(tRequest, .pDecision)
		Set pSessionId = tService.%SessionId
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
