/// Sends the review tasks a mapping revoke creates (Settings.Store.RevokeMapping) to the
/// Workflow operation. Fire and forget: the answer closes the task and acts on nothing, since a
/// message that went out with a bad code is corrected by a person at the receiver.
Class AgenticProd.Service.MemoryReview Extends Ens.BusinessService
{

/// Workflow operation (role) that gets the review tasks.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "IntegrationSupport" ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnProcessInput(pInput As AgenticProd.Msg.ApprovalTask, Output pOutput As %RegisteredObject) As %Status
{
	Quit ..SendRequestAsync(..TargetConfigName, pInput, 0)
}

/// Send every task in pTasks through config item "MemoryReview" of the running production.
/// pSent = tasks sent; an error when the production is not running or the item is missing.
ClassMethod Send(pTasks As %ListOfObjects, Output pSent As %Integer) As %Status
{
	Set pSent = 0
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(Ens.Director).CreateBusinessService("MemoryReview", .tService))
		For i = 1:1:pTasks.Count() {
			$$$ThrowOnError(tService.ProcessInput(pTasks.GetAt(i)))
			Set pSent = pSent + 1
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
