/// One LabCodeMap entry with its provenance: a seed from Setup or a mapping a reviewer approved.
/// A learned mapping is memory the router acts on without asking the agent again, so it keeps
/// where it came from and can be revoked (Settings, Memory). Never purged.
Class AgenticProd.Data.LearnedMapping Extends %Persistent
{

Property LocalCode As %String(MAXLEN = 100) [ Required ];

/// Sending application. LabCodeMap is not per source yet, so it is informational.
Property Source As %String(MAXLEN = 128);

Property Loinc As %String(MAXLEN = 20) [ Required ];

Property Display As %String(MAXLEN = 500);

Property Origin As %String(VALUELIST = ",Seed,Approved") [ Required ];

/// Approved: the DecisionLog row of the MAP_CODE decision, for its story view.
Property DecisionLogId As %Integer;

Property AgentSessionId As %String(MAXLEN = 50);

/// Evidence lines of the decision, one per line.
Property Evidence As %String(MAXLEN = "");

Property Reviewer As %String(MAXLEN = 128);

/// UTC. Seeds get the time Setup wrote them.
Property ApprovedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

/// Why the approved LOINC was taken despite a failed check (not in the KB), or the reviewer's
/// note when a revoked mapping was learned again.
Property Warning As %String(MAXLEN = 1000);

Property Status As %String(VALUELIST = ",Active,Revoked") [ InitialExpression = "Active", Required ];

Property RevokedBy As %String(MAXLEN = 128);

Property RevokedAt As %TimeStamp;

Property RevokeReason As %String(MAXLEN = 1000);

Index CodeIdx On (LocalCode, Status);

/// A new approval replaces the LabCodeMap entry, so older Active rows of pCode are closed as
/// Revoked by "system". RevokedNote skips those: only a person's revoke blocks re-learning.
ClassMethod Supersede(pCode As %String, pExceptId As %String = "") As %Status [ Internal ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "UPDATE AgenticProd_Data.LearnedMapping SET Status = 'Revoked', RevokedBy = 'system', RevokedAt = ?, RevokeReason = 'replaced by a newer mapping' WHERE LocalCode = ? AND Status = 'Active' AND ID <> ?", $ZDATETIME($ZTIMESTAMP, 3), pCode, +pExceptId)
	Quit:tRS.%SQLCODE<0 $$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message)
	Quit $$$OK
}

/// Record a seed row for pCode unless an Active row for it already exists (Setup runs again).
ClassMethod Seed(pCode As %String, pLoinc As %String, pDisplay As %String) As %Status
{
	Quit:..ActiveId(pCode)'="" $$$OK
	Set tRow = ..%New()
	Set tRow.LocalCode = pCode, tRow.Loinc = pLoinc, tRow.Display = pDisplay, tRow.Origin = "Seed", tRow.Reviewer = "Setup"
	Quit tRow.%Save()
}

/// Record an approved mapping and supersede the older Active row of the same code.
ClassMethod Approved(pCode As %String, pSource As %String, pLoinc As %String, pDisplay As %String, pLogId As %String, pAgentSessionId As %String, pEvidence As %String, pReviewer As %String, pWarning As %String = "", Output pId As %String) As %Status
{
	Set pId = ""
	Set tSC = $$$OK
	Try {
		Set tRow = ..%New()
		Set tRow.LocalCode = pCode, tRow.Source = pSource, tRow.Loinc = pLoinc, tRow.Display = pDisplay
		Set tRow.Origin = "Approved", tRow.DecisionLogId = pLogId, tRow.AgentSessionId = pAgentSessionId
		Set tRow.Evidence = pEvidence, tRow.Reviewer = pReviewer, tRow.Warning = $EXTRACT(pWarning, 1, 1000)
		$$$ThrowOnError(tRow.%Save())
		Set pId = tRow.%Id()
		$$$ThrowOnError(..Supersede(pCode, pId))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// ID of the Active row for pCode, "" if none.
ClassMethod ActiveId(pCode As %String) As %String
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.LearnedMapping WHERE LocalCode = ? AND Status = 'Active' ORDER BY ID DESC", pCode)
	Quit $SELECT(tRS.%Next(): tRS.ID, 1: "")
}

/// The latest revoke of pCode -> pLoinc by a person (not a supersede), as "by on: reason";
/// "" when that pair was never revoked, or was learned again since (with a reviewer's note).
ClassMethod RevokedNote(pCode As %String, pLoinc As %String) As %String
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.LearnedMapping WHERE LocalCode = ? AND Loinc = ? AND Status = 'Active'", pCode, pLoinc)
	Quit:tRS.%Next() ""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 RevokedBy, RevokedAt, RevokeReason FROM AgenticProd_Data.LearnedMapping WHERE LocalCode = ? AND Loinc = ? AND Status = 'Revoked' AND RevokedBy <> 'system' ORDER BY ID DESC", pCode, pLoinc)
	Quit:'tRS.%Next() ""
	Quit tRS.RevokedBy_" on "_tRS.RevokedAt_": "_tRS.RevokeReason
}

Storage Default
{
<Data name="LearnedMappingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>LocalCode</Value>
</Value>
<Value name="3">
<Value>Source</Value>
</Value>
<Value name="4">
<Value>Loinc</Value>
</Value>
<Value name="5">
<Value>Display</Value>
</Value>
<Value name="6">
<Value>Origin</Value>
</Value>
<Value name="7">
<Value>DecisionLogId</Value>
</Value>
<Value name="8">
<Value>AgentSessionId</Value>
</Value>
<Value name="9">
<Value>Evidence</Value>
</Value>
<Value name="10">
<Value>Reviewer</Value>
</Value>
<Value name="11">
<Value>ApprovedAt</Value>
</Value>
<Value name="12">
<Value>Warning</Value>
</Value>
<Value name="13">
<Value>Status</Value>
</Value>
<Value name="14">
<Value>RevokedBy</Value>
</Value>
<Value name="15">
<Value>RevokedAt</Value>
</Value>
<Value name="16">
<Value>RevokeReason</Value>
</Value>
</Data>
<DataLocation>^AgenticProd8110.LearnedMappingD</DataLocation>
<DefaultData>LearnedMappingDefaultData</DefaultData>
<IdLocation>^AgenticProd8110.LearnedMappingD</IdLocation>
<IndexLocation>^AgenticProd8110.LearnedMappingI</IndexLocation>
<StreamLocation>^AgenticProd8110.LearnedMappingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
