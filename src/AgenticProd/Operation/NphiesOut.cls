Include Ensemble

/// Simulated NPHIES receiver: writes each message to the adapter FilePath. A message whose MSH-10
/// is in SimulateTimeoutFor fails its first send with a timeout, so the TRANSIENT and RESEND path
/// can be shown; the resend of the same message gets through.
Class AgenticProd.Operation.NphiesOut Extends EnsLib.HL7.Operation.FileOperation
{

/// Comma-separated MSH-10 control IDs whose first send times out.
Property SimulateTimeoutFor As %String(MAXLEN = 1000) [ InitialExpression = "MSG00015" ];

Parameter SETTINGS = "SimulateTimeoutFor:Simulation";

Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As EnsLib.HL7.Message) As %Status
{
	Set tControlId = pRequest.GetValueAt("1:10")
	If tControlId '= "", (","_..SimulateTimeoutFor_",") [ (","_tControlId_","), '$DATA(^AgenticProd.NphiesOut("timedout", tControlId)) {
		// Keyed by MSH-10, not the message ID: a resend is a new message with the same control ID
		Set ^AgenticProd.NphiesOut("timedout", tControlId) = $ZDATETIME($ZTIMESTAMP, 3)
		Quit $$$ERROR($$$GeneralError, "Timed out waiting for response from NphiesOut (HTTP 504, simulated for "_tControlId_")")
	}
	Quit ##super(pRequest, .pResponse)
}

/// Forget past simulated timeouts, so the next send of those messages times out again.
ClassMethod ResetSimulation()
{
	Kill ^AgenticProd.NphiesOut("timedout")
}

}
