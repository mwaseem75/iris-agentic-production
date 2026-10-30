Include Ensemble

/// Plug-in entry point in a customer production: turns each failure the SentinelAdapter finds
/// into a TriageRequest for the plug-in's Triage. Reads the failed message, changes nothing.
Class AgenticProd.Plugin.Sentinel Extends Ens.BusinessService
{

Parameter ADAPTER = "AgenticProd.Plugin.SentinelAdapter";

/// Triage item of the plug-in.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "AI.Triage" ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

/// pInput.StringValue is the failed header ID.
Method OnProcessInput(pInput As Ens.StringContainer, Output pOutput As %RegisteredObject) As %Status
{
	Set tSC = ..BuildRequest(pInput.StringValue, .tRequest)
	Quit:$$$ISERR(tSC) tSC
	$$$TRACE("Sentinel: header "_tRequest.HeaderId_" ("_tRequest.Format_", session "_tRequest.SessionId_") to "_..TargetConfigName)
	Quit ..SendRequestAsync(..TargetConfigName, tRequest)
}

/// TriageRequest for failed header pHeaderId of this namespace. HL7 v2 bodies get the same
/// Source, control ID and InjectionGuard flags LabRouter gives its own failures; any other body
/// goes as its class name, which Triage escalates without an agent run (no fix checker).
/// ErrorText is the header's error status and the session's error events.
ClassMethod BuildRequest(pHeaderId As %Integer, Output pRequest As AgenticProd.Msg.TriageRequest) As %Status
{
	Set pRequest = ""
	Set tSC = $$$OK
	Try {
		Set tHeader = ##class(Ens.MessageHeader).%OpenId(pHeaderId, , .tSC)
		$$$ThrowOnError(tSC)
		Set pRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
		Set pRequest.HeaderId = pHeaderId, pRequest.SessionId = tHeader.SessionId
		Set pRequest.Source = tHeader.SourceConfigName, pRequest.Format = $EXTRACT(tHeader.MessageBodyClassName, 1, 20)
		Set tText = $SELECT($$$ISERR(tHeader.ErrorStatus):$SYSTEM.Status.GetErrorText(tHeader.ErrorStatus), 1: "")
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? AND %EXTERNAL(Type) IN ('Error', 'Alert') ORDER BY ID", tHeader.SessionId)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While tRS.%Next() {
			Set tText = tText_$SELECT(tText '= "": "; ", 1: "")_"["_tRS.ConfigName_"] "_tRS.Text
		}
		Set pRequest.ErrorText = $EXTRACT(tText, 1, 4000)
		If tHeader.MessageBodyClassName = "EnsLib.HL7.Message" {
			Set tMsg = ##class(EnsLib.HL7.Message).%OpenId(tHeader.MessageBodyId)
			If $IsObject(tMsg) {
				// Triage's CHECKERS key for HL7 v2
				Set pRequest.Format = "HL7v2"
				Set pRequest.Source = tMsg.GetValueAt("1:3.1"), pRequest.ControlId = tMsg.GetValueAt("1:10")
				Do ##class(AgenticProd.Process.LabRouter).ScanFreeText(tMsg, pRequest.Flags)
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus(), pRequest = ""
	}
	Quit tSC
}

}
