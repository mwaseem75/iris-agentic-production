Include Ensemble

/// HL7 v2 lab results in: check the message type, validate against the NPHIES_SIM profile, look up
/// every OBX-3.1 in LabCodeMap, transform and send to NphiesOut. Any failure becomes a
/// TriageRequest to Triage; the router never repairs a message itself.
Class AgenticProd.Process.LabRouter Extends Ens.BusinessProcess
{

/// When several checks fail, the router's first guess at error_class is the first of these found.
Parameter CLASSORDER = "ROUTING,IDENTITY_ISSUE,STRUCTURE_ERROR,MISSING_FIELD,BAD_FORMAT,INVALID_VALUE,UNMAPPED_CODE,OTHER";

/// Receiver of the transformed message.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "NphiesOut" ];

/// Where failed messages go as a TriageRequest.
Property TriageTarget As Ens.DataType.ConfigName [ InitialExpression = "Triage" ];

/// Seconds to wait for TargetConfigName before the send counts as TRANSIENT.
Property SendTimeout As %Integer(MINVAL = 1) [ InitialExpression = 30 ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},TriageTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},SendTimeout:Basic";

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pResponse As %Library.Persistent) As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..Check(pRequest, .tClass, .tText))
		If tClass = "" {
			Set tSC = ##class(AgenticProd.DTL.LabToNphies).Transform(pRequest, .tOut)
			If $$$ISERR(tSC) {
				Set tClass = "OTHER", tText = "DTL LabToNphies failed: "_$SYSTEM.Status.GetErrorText(tSC)
			} Else {
				Set tSC = ..SendRequestSync(..TargetConfigName, tOut, .tResponse, ..SendTimeout)
				// The content passed every check, so a failed send is the receiver's problem
				If $$$ISERR(tSC) Set tClass = "TRANSIENT", tText = ..TargetConfigName_" failed: "_$SYSTEM.Status.GetErrorText(tSC)
			}
			Set tSC = $$$OK
		}
		Quit:tClass=""
		$$$TRACE("LabRouter to "_..TriageTarget_": "_tClass_" "_tText)
		$$$ThrowOnError(..SendRequestAsync(..TriageTarget, ..TriageRequest(pRequest, tClass, tText), 0))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Run every check on pMsg. pClass is "" when it may be sent, else the first class found in
/// CLASSORDER. pText lists every problem, so the agent sees them all (e.g. eval case 16).
ClassMethod Check(pMsg As EnsLib.HL7.Message, Output pClass As %String, Output pText As %String) As %Status
{
	Set (pClass, pText) = ""
	Set tType = pMsg.GetValueAt("1:9.1")_"^"_pMsg.GetValueAt("1:9.2")
	If tType '= "ORU^R01" {
		Set pClass = "ROUTING", pText = "Routing: MSH-9 '"_tType_"' is not ORU^R01; LabRouter only takes lab results"
		Quit $$$OK
	}
	// Same profile as validate_fix, so a fix that passes there passes here
	Do ##class(AgenticProd.Tools.HL7).ValidationErrors(pMsg, .tErrors)
	Set tIter = tErrors.%GetIterator()
	While tIter.%GetNext(, .tError) {
		Set tFound(..ClassOf(tError)) = ""
		Set pText = pText_$SELECT(pText '= "": "; ", 1: "")_"Validation: "_tError
	}
	Set tSource = pMsg.GetValueAt("1:3.1"), tOcc = 0
	For i = 1:1:pMsg.SegCount {
		Set tSeg = pMsg.GetSegmentAt(i)
		Continue:'$IsObject(tSeg)
		Continue:tSeg.Name'="OBX"
		Set tOcc = tOcc + 1, tCode = tSeg.GetValueAt("3.1")
		Continue:(tCode'="")&&(##class(Ens.Util.FunctionSet).Lookup("LabCodeMap", tCode)'="")
		Set tFound("UNMAPPED_CODE") = ""
		Set pText = pText_$SELECT(pText '= "": "; ", 1: "")_"Lookup LabCodeMap: no entry for OBX("_tOcc_"):3.1 '"_tCode_"' from "_tSource
	}
	For i = 1:1:$LENGTH(..#CLASSORDER, ",") {
		Set tClass = $PIECE(..#CLASSORDER, ",", i)
		If $DATA(tFound(tClass)) Set pClass = tClass  Quit
	}
	Quit $$$OK
}

/// Error class for one Tools.HL7.ValidationErrors entry.
ClassMethod ClassOf(pError As %String) As %String
{
	// Profile errors start with a segment reference such as OBX(1):14; the rest are IRIS structure errors
	Quit:'$MATCH(pError, "[A-Z][A-Z0-9]{2}\(\d+\):\d+.*") "STRUCTURE_ERROR"
	Quit:$EXTRACT(pError, 1, 4)="PID(" "IDENTITY_ISSUE"
	Quit:pError["required" "MISSING_FIELD"
	Quit:(pError["not a valid TS")||(pError["not a valid NM")||(pError["not a valid SN") "BAD_FORMAT"
	Quit:pError["not in HL7 table" "INVALID_VALUE"
	Quit "OTHER"
}

/// HeaderId is the header of the message this router received, so Triage, the agent tools
/// and a RESEND all work on the original body.
Method TriageRequest(pMsg As EnsLib.HL7.Message, pClass As %String, pText As %String) As AgenticProd.Msg.TriageRequest
{
	Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
	Set tRequest.HeaderId = ..%PrimaryRequestHeader.%Id()
	Set tRequest.SessionId = ..%SessionId
	Set tRequest.Source = pMsg.GetValueAt("1:3.1")
	Set tRequest.Format = "HL7v2"
	Set tRequest.ErrorText = pText
	Set tRequest.ErrorClass = pClass
	Quit tRequest
}

Storage Default
{
<Data name="LabRouterDefaultData">
<Subscript>"LabRouter"</Subscript>
<Value name="1">
<Value>TargetConfigName</Value>
</Value>
<Value name="2">
<Value>TriageTarget</Value>
</Value>
<Value name="3">
<Value>SendTimeout</Value>
</Value>
</Data>
<DefaultData>LabRouterDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
