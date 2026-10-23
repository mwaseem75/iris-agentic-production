/// Seeding and one-time configuration. Safe to run again: everything is create-or-update.
Class AgenticProd.Setup
{

/// Role and user the agent operation job switches to (Operation.Agent RunAsUser).
Parameter AGENTROLE = "AgenticProd_Agent";

Parameter AGENTUSER = "agentic_agent";

/// Database resources only cover what an interop job needs to store messages and read code.
/// Data access inside IRISAPP_DATA is still all-or-nothing for globals; SQL grants narrow it
/// for %SQL.Statement, which is the only way agent tools may query.
Parameter AGENTRESOURCES = "%DB_IRISAPP_DATA:RW,%DB_IRISAPP_CODE:R,%DB_ENSLIB:R,%DB_HSLIB:R,%DB_HSSYS:R,%DB_IRISLIB:R,%DB_IRISSYS:R,%DB_IRISTEMP:RW";

ClassMethod Run() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(AgenticProd.Data.PriceTable).Seed())
		$$$ThrowOnError(..AgentSecurity())
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Create or update the agent role and user, then the SQL grants:
/// SELECT on the schemas tools read, INSERT only on the three audit/usage tables, nothing else.
ClassMethod AgentSecurity() As %Status
{
	Set tSC = $$$OK
	Try {
		Set tNS = $NAMESPACE
		$$$ThrowOnError(..CreateRoleAndUser(tNS))
		For tSql = "GRANT SELECT ON SCHEMA AgenticProd_Data TO "_..#AGENTROLE,
			"GRANT SELECT ON SCHEMA Ens TO "_..#AGENTROLE,
			"GRANT SELECT ON SCHEMA Ens_Util TO "_..#AGENTROLE,
			"GRANT INSERT ON AgenticProd_Data.ToolCall, AgenticProd_Data.Usage, AgenticProd_Data.DecisionLog TO "_..#AGENTROLE {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSql)
			If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message_" ("_tSql_")"))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod CreateRoleAndUser(pNamespace As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set tSC = $$$OK
	Try {
		Set tDesc = "AgenticProd triage agent job: message storage, SELECT-only SQL"
		If ##class(Security.Roles).Exists(..#AGENTROLE) {
			Set tProps("Description") = tDesc
			Set tProps("Resources") = ..#AGENTRESOURCES
			$$$ThrowOnError(##class(Security.Roles).Modify(..#AGENTROLE, .tProps))
		} Else {
			$$$ThrowOnError(##class(Security.Roles).Create(..#AGENTROLE, tDesc, ..#AGENTRESOURCES))
		}
		// Random password nobody keeps, and no %Service_* role: nobody can log in as this user.
		// The agent job enters it with $SYSTEM.Security.Login from a privileged process.
		If '##class(Security.Users).Exists(..#AGENTUSER) {
			$$$ThrowOnError(##class(Security.Users).Create(..#AGENTUSER, ..#AGENTROLE, $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(24)), "AgenticProd agent job", pNamespace))
		} Else {
			Kill tProps
			Set tProps("Roles") = ..#AGENTROLE
			Set tProps("Enabled") = 1
			$$$ThrowOnError(##class(Security.Users).Modify(..#AGENTUSER, .tProps))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
