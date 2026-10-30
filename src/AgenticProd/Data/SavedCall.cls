/// One message that passed LabRouter's lookup only because of a mapping a reviewer approved
/// (DecisionLog Outcome APPROVED): without it the message would have gone to the agent.
/// Written by LabRouter; never purged. The resend of the approved message itself is not counted.
Class AgenticProd.Data.SavedCall Extends %Persistent
{

Property HeaderId As %Integer;

/// Namespace the row's header and session IDs belong to: they are only unique within it
/// (IRISAPP, or a plug-in namespace such as LEGACY that shares this table).
Property Namespace As %String(MAXLEN = 64) [ InitialExpression = {$NAMESPACE} ];

/// Learned local codes the message used, comma separated.
Property LocalCodes As %String(MAXLEN = 500);

Property EvalRunId As %Integer;

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Index CreatedIdx On CreatedAt;

/// Record pMsg (header pHeaderId) when one of its OBX-3.1 codes was learned. Call it only for a
/// message that passed every check. Never fails the message: errors come back as a status.
ClassMethod Note(pMsg As EnsLib.HL7.Message, pHeaderId As %Integer) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tCodes = ""
		For i = 1:1:pMsg.SegCount {
			Set tSeg = pMsg.GetSegmentAt(i)
			Continue:'$IsObject(tSeg)
			Continue:tSeg.Name'="OBX"
			Set tCode = tSeg.GetValueAt("3.1")
			Continue:(tCode="")||$DATA(tSeen(tCode))
			Set tSeen(tCode) = ""
			// Learned, and not the resend of any approval of this code (same body as the approved message)
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 d.ID FROM AgenticProd_Data.DecisionLog d WHERE d.LocalCode = ? AND d.Outcome = 'APPROVED'"
				_" AND NOT EXISTS (SELECT 1 FROM AgenticProd_Data.DecisionLog a JOIN Ens.MessageHeader h ON h.ID = a.HeaderId"
				_" WHERE a.LocalCode = ? AND a.Outcome = 'APPROVED' AND a.Namespace = ? AND h.MessageBodyId = ?)", tCode, tCode, $NAMESPACE, pMsg.%Id())
			If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
			Set:tRS.%Next() tCodes = tCodes_$SELECT(tCodes '= "": ",", 1: "")_tCode
		}
		Quit:tCodes=""
		Set tRow = ..%New()
		Set tRow.HeaderId = pHeaderId, tRow.LocalCodes = $EXTRACT(tCodes, 1, 500)
		Do ##class(AgenticProd.Eval.Runner).CaseOf(pMsg.GetValueAt("1:10"), .tRunId)
		Set tRow.EvalRunId = tRunId
		$$$ThrowOnError(tRow.%Save())
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Storage Default
{
<Data name="SavedCallDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>HeaderId</Value>
</Value>
<Value name="3">
<Value>LocalCodes</Value>
</Value>
<Value name="4">
<Value>EvalRunId</Value>
</Value>
<Value name="5">
<Value>CreatedAt</Value>
</Value>
<Value name="6">
<Value>Namespace</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.SavedCallD</DataLocation>
<DefaultData>SavedCallDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.SavedCallD</IdLocation>
<IndexLocation>^AgenticProd.Data.SavedCallI</IndexLocation>
<StreamLocation>^AgenticProd.Data.SavedCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
