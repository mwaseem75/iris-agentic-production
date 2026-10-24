Include Ensemble

/// Stand-in for the human approval step until the EnsLib.Workflow task (4.4): logs each MAP_CODE
/// or ESCALATE decision as a warning, so it shows in the Event Log and Visual Trace. Approves nothing.
Class AgenticProd.Operation.ApprovalStub Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method Approve(pRequest As AgenticProd.Msg.Decision, Output pResponse As Ens.Response) As %Status
{
	$$$LOGWARNING("Approval needed: "_pRequest.Decision_" "_pRequest.ErrorClass_" confidence "_pRequest.Confidence_": "_pRequest.Reason)
	Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="AgenticProd.Msg.Decision">
    <Method>Approve</Method>
  </MapItem>
</MapItems>
}

}
