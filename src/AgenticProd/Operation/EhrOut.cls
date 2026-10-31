Include Ensemble

/// Simulated hospital EHR receiver: writes each message to the adapter FilePath. A message listed in
/// SimulateTimeoutFor fails its first send with a timeout, so the TRANSIENT and RESEND path
/// can be shown; the resend of the same message gets through.
Class AgenticProd.Operation.EhrOut Extends EnsLib.HL7.Operation.FileOperation
{

/// Comma-separated MSH-10 control IDs or eval case IDs whose first send times out.
/// A case ID matches the eval control ID EV<runId>-<caseId>.
Property SimulateTimeoutFor As %String(MAXLEN = 1000) [ InitialExpression = "MSG00015,15" ];

Parameter SETTINGS = "SimulateTimeoutFor:Simulation";

Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As EnsLib.HL7.Message) As %Status
{
	Set tControlId = pRequest.GetValueAt("1:10")
	If ..IsSimulated(..SimulateTimeoutFor, tControlId), '$DATA(^AgenticProd.EhrOut("timedout", tControlId)) {
		// Keyed by MSH-10, not the message ID: a resend is a new message with the same control ID
		Set ^AgenticProd.EhrOut("timedout", tControlId) = $ZDATETIME($ZTIMESTAMP, 3)
		Quit $$$ERROR($$$GeneralError, "Timed out waiting for response from EhrOut (HTTP 504, simulated for "_tControlId_")")
	}
	Quit ##super(pRequest, .pResponse)
}

/// Every file is <MSH-10>_<timestamp>.hl7. The FileOperation default uses the source file name,
/// which a message built by Triage does not have.
Method outputDocument(pFilename As %String, pDocument As EnsLib.HL7.Message, pSeparators As %String, pDoFraming As %Integer) As %Status
{
	Quit ##super(..Adapter.CreateFilename(pDocument.GetValueAt("1:10"), "%f_%Q.hl7"), pDocument, .pSeparators, .pDoFraming)
}

/// 1 if pControlId, or the eval case ID inside it, is in the comma-separated pList.
ClassMethod IsSimulated(pList As %String, pControlId As %String) As %Boolean
{
	Quit:pControlId="" 0
	Set tList = ","_$ZSTRIP(pList, "*W")_","
	Quit:tList[(","_pControlId_",") 1
	Set tCase = ##class(AgenticProd.Eval.Runner).CaseOf(pControlId)
	Quit (tCase '= "") && (tList [ (","_tCase_","))
}

/// Forget past simulated timeouts, so the next send of those messages times out again.
ClassMethod ResetSimulation()
{
	Kill ^AgenticProd.EhrOut("timedout")
}

}
