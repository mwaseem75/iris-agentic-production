Include Ensemble

/// Polls the production's own message headers and event log for failures, the way an inbound
/// adapter polls a folder: errored or suspended headers, and alerts that belong to a session.
/// Hands each failed session's header ID (once) to the Sentinel service. High-water marks are
/// kept per config item in ^Ens.AppData, so a restart does not hand the same failure on again.
Class AgenticProd.Plugin.SentinelAdapter Extends Ens.InboundAdapter
{

/// Seconds a header must be old before it is looked at: by then its status is final.
Property SettleSeconds As %Integer(MINVAL = 0) [ InitialExpression = 10 ];

/// Failures handed on per poll, so a backlog does not flood the agent.
Property MaxPerPoll As %Integer(MINVAL = 1) [ InitialExpression = 5 ];

/// Config name prefix of the plug-in's own items; messages to or from them are never picked up,
/// so a failing Triage or agent call cannot feed itself.
Property OwnPrefix As %String(MAXLEN = 20) [ InitialExpression = "AI." ];

Parameter SETTINGS = "SettleSeconds:Sentinel,MaxPerPoll:Sentinel,OwnPrefix:Sentinel";

/// First start: marks at the newest header and log entry, so the plug-in watches failures from
/// now on and an old backlog never turns into a burst of agent calls.
Method OnInit() As %Status
{
	Do:'$DATA($$$EnsStaticAppData(..BusinessHost.%ConfigName, "header")) ..MarkNow(..BusinessHost.%ConfigName)
	Quit $$$OK
}

/// Set pKey's marks to the newest header and log entry.
ClassMethod MarkNow(pKey As %String) [ Internal ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) AS H FROM Ens.MessageHeader")
	Set $$$EnsStaticAppData(pKey, "header") = $SELECT(tRS.%Next(): +tRS.H, 1: 0)
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) AS L FROM Ens_Util.Log")
	Set $$$EnsStaticAppData(pKey, "log") = $SELECT(tRS.%Next(): +tRS.L, 1: 0)
}

Method OnTask() As %Status
{
	Set tSC = $$$OK
	Try {
		Set tKey = ..BusinessHost.%ConfigName
		// Marks gone while the job runs (removed by Disable): start again from now, never from 0,
		// or every old failure in the namespace would go to the agent
		If '$DATA($$$EnsStaticAppData(tKey, "header")) {
			Do ..MarkNow(tKey)
			Quit
		}
		Set tAfterHdr = +$GET($$$EnsStaticAppData(tKey, "header")), tAfterLog = +$GET($$$EnsStaticAppData(tKey, "log"))
		$$$ThrowOnError(..Scan(tAfterHdr, tAfterLog, ..SettleSeconds, ..MaxPerPoll, ..OwnPrefix, .tFound, .tLastHdr, .tLastLog))
		For i = 1:1:tFound {
			$$$ThrowOnError(..BusinessHost.ProcessInput(##class(Ens.StringContainer).%New(tFound(i))))
		}
		// Marks move only after every hand-on succeeded; a failed one is picked up again next poll
		Set $$$EnsStaticAppData(tKey, "header") = tLastHdr, $$$EnsStaticAppData(tKey, "log") = tLastLog
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Set ..BusinessHost.%WaitForNextCallInterval = 1
	Quit tSC
}

/// Failed headers after pAfterHdr and alert log entries after pAfterLog, settled for pSettle
/// seconds, at most pMax sessions: pFound(n) = header ID, one per session, skipping sessions this
/// namespace already has a DecisionLog row for. pLastHdr and pLastLog are the new marks: the last
/// header and log entry looked at, so a later poll starts after them.
ClassMethod Scan(pAfterHdr As %Integer, pAfterLog As %Integer, pSettle As %Integer, pMax As %Integer, pOwnPrefix As %String, Output pFound, Output pLastHdr As %Integer, Output pLastLog As %Integer) As %Status
{
	Kill pFound
	Set pFound = 0, pLastHdr = pAfterHdr, pLastLog = pAfterLog
	Set tSC = $$$OK
	Try {
		Set tBefore = $ZDATETIME($ZDATETIMEH($ZDATETIME($ZTIMESTAMP, -2) - pSettle, -2), 3)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, IsError, %EXTERNAL(Status) AS Status, SourceConfigName, TargetConfigName FROM Ens.MessageHeader"
			_" WHERE ID > ? AND TimeCreated <= ? ORDER BY ID", pAfterHdr, tBefore)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While (pFound < pMax) && tRS.%Next() {
			Set pLastHdr = tRS.ID
			Continue:'tRS.IsError&&(tRS.Status'="Suspended")&&(tRS.Status'="Error")
			Continue:..IsOwn(tRS.SourceConfigName, pOwnPrefix)||..IsOwn(tRS.TargetConfigName, pOwnPrefix)
			Do ..Add(tRS.SessionId, tRS.ID, .pFound)
		}
		Quit:pFound>=pMax
		// Alerts point at a session; one with no session (adapter down at startup) has no message to triage
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, ConfigName FROM Ens_Util.Log WHERE ID > ? AND %EXTERNAL(Type) = 'Alert' AND TimeLogged <= ? ORDER BY ID", pAfterLog, tBefore)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While (pFound < pMax) && tRS.%Next() {
			Set pLastLog = tRS.ID
			Continue:(tRS.SessionId="")||..IsOwn(tRS.ConfigName, pOwnPrefix)
			// A session ID is the ID of the session's first header
			Do ..Add(tRS.SessionId, tRS.SessionId, .pFound)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Add pHeaderId for pSessionId unless the session was already added or triaged here.
ClassMethod Add(pSessionId As %Integer, pHeaderId As %Integer, ByRef pFound) [ Internal ]
{
	Quit:$DATA(pFound("s", pSessionId))
	Set pFound("s", pSessionId) = ""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.DecisionLog WHERE SessionId = ? AND Namespace = ?", pSessionId, $NAMESPACE)
	Quit:tRS.%Next()
	Set pFound($INCREMENT(pFound)) = pHeaderId
}

ClassMethod IsOwn(pConfigName As %String, pPrefix As %String) As %Boolean [ Internal ]
{
	Quit (pPrefix '= "") && ($EXTRACT(pConfigName, 1, $LENGTH(pPrefix)) = pPrefix)
}

}
