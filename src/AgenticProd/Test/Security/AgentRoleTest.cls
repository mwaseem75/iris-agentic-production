/// SQL privileges of the agent role, checked in a child job that switches to the agent user the
/// way Operation.Agent does, so the test process keeps its own rights. Needs Setup.AgentSecurity().
Class AgenticProd.Test.Security.AgentRoleTest Extends AgenticProd.Test.Case
{

Method TestAgentSqlIsSelectOnlyPlusAuditInserts()
{
	Set tUser = ##class(AgenticProd.Setup).#AGENTUSER
	Kill ^AgenticProd.Test.RoleProbe
	Job ##class(AgenticProd.Test.Security.AgentRoleTest).Probe(tUser)::10
	If '$TEST {
		Do $$$AssertFailure("could not start the probe job")
		Quit
	}
	// FastEmbed loads its model in the new process, so the probe can take several seconds
	For i = 1:1:150 Quit:$DATA(^AgenticProd.Test.RoleProbe("done"))  Hang 0.2
	Do $$$AssertTrue($DATA(^AgenticProd.Test.RoleProbe("done")), "probe job finished")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("login")), 1, "job switched to "_tUser)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("user")), tUser)
	Do $$$AssertNotTrue($GET(^AgenticProd.Test.RoleProbe("roles")) [ "%All", "no %All after the switch")

	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("select")), 0, "SELECT allowed")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("insert")), 0, "INSERT on Usage allowed")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("update")), -99, "UPDATE refused (SQLCODE -99)")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("delete")), -99, "DELETE refused (SQLCODE -99)")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("insertOther")), -99, "INSERT on a non-audit table refused")
	// Mapping tools read the KB table and the lookup table; both need the role's SELECT grants
	Do $$$AssertTrue($GET(^AgenticProd.Test.RoleProbe("search")) [ "2345-7", "search_loinc works as the agent: "_$EXTRACT($GET(^AgenticProd.Test.RoleProbe("search")), 1, 200))
	Do $$$AssertTrue($GET(^AgenticProd.Test.RoleProbe("lookup")) [ "2951-2", "lookup_code works as the agent: "_$GET(^AgenticProd.Test.RoleProbe("lookup")))
}

/// The same grants in the plug-in namespace (SQL privileges are per namespace), where the agent
/// job of a plug-in production runs; the shared Data tables are mapped there.
Method TestAgentSqlInPluginNamespace()
{
	Set tUser = ##class(AgenticProd.Setup).#AGENTUSER, tNS = ##class(AgenticProd.Setup).#LEGACYNS
	Kill ^AgenticProd.Test.RoleProbe
	Job ##class(AgenticProd.Test.Security.AgentRoleTest).ProbeIn(tUser, tNS)::10
	If '$TEST {
		Do $$$AssertFailure("could not start the probe job")
		Quit
	}
	For i = 1:1:50 Quit:$DATA(^AgenticProd.Test.RoleProbe("done"))  Hang 0.2
	Do $$$AssertTrue($DATA(^AgenticProd.Test.RoleProbe("done")), "probe job finished")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("login")), 1, "job switched to "_tUser)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("select")), 0, "SELECT on shared Data allowed in "_tNS)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("header")), 0, "SELECT on "_tNS_" headers allowed")
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("insert")), 0, "INSERT on Usage allowed in "_tNS)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("update")), -99, "UPDATE refused in "_tNS)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("delete")), -99, "DELETE refused in "_tNS)
	Do $$$AssertEquals($GET(^AgenticProd.Test.RoleProbe("insertOther")), -99, "INSERT on a non-audit table refused in "_tNS)
}

/// Child job for the plug-in namespace test. Results are kept in locals until the job is back in
/// this namespace: the probe global is not mapped into pNamespace.
ClassMethod ProbeIn(pUser As %String, pNamespace As %String)
{
	Set tHome = $NAMESPACE
	Set tRes("login") = $SYSTEM.Security.Login(pUser)
	Try {
		Set $NAMESPACE = pNamespace
		For tKey = "select", "header", "insert", "update", "delete", "insertOther" {
			Set tSql = $CASE(tKey,
				"select": "SELECT COUNT(*) FROM AgenticProd_Data.DecisionLog",
				"header": "SELECT TOP 1 ID FROM Ens.MessageHeader",
				"insert": "INSERT INTO AgenticProd_Data.Usage (HeaderId, Model) VALUES (-9103, 'role-probe')",
				"update": "UPDATE AgenticProd_Data.DecisionLog SET Outcome = 'probe' WHERE 1 = 0",
				"delete": "DELETE FROM AgenticProd_Data.Usage WHERE HeaderId = -9103",
				"insertOther": "INSERT INTO AgenticProd_Data.PriceTable (Model) VALUES ('role-probe')")
			Try {
				Set tRes(tKey) = ##class(%SQL.Statement).%ExecDirect(, tSql).%SQLCODE
			} Catch ex {
				Set tRes(tKey) = "exception: "_ex.DisplayString()
			}
		}
	} Catch ex {
		Set tRes("select") = "exception: "_ex.DisplayString()
	}
	Set $NAMESPACE = tHome
	Merge ^AgenticProd.Test.RoleProbe = tRes
	Set ^AgenticProd.Test.RoleProbe("done") = 1
}

/// Child job body. Uses %SQL.Statement, the same path agent tools must use; embedded SQL
/// skips privilege checks, so it would prove nothing here.
ClassMethod Probe(pUser As %String)
{
	// Same order as Operation.Agent.OnInit
	Do ##class(AgenticProd.Tools.Mapping).Prepare()
	Set ^AgenticProd.Test.RoleProbe("login") = $SYSTEM.Security.Login(pUser)
	Set ^AgenticProd.Test.RoleProbe("user") = $USERNAME
	Set ^AgenticProd.Test.RoleProbe("roles") = $ROLES
	For tKey = "select", "insert", "update", "delete", "insertOther" {
		Set tSql = $CASE(tKey,
			"select": "SELECT COUNT(*) FROM AgenticProd_Data.Usage",
			"insert": "INSERT INTO AgenticProd_Data.Usage (HeaderId, Model) VALUES (-9103, 'role-probe')",
			"update": "UPDATE AgenticProd_Data.DecisionLog SET Outcome = 'probe' WHERE 1 = 0",
			"delete": "DELETE FROM AgenticProd_Data.Usage WHERE HeaderId = -9103",
			"insertOther": "INSERT INTO AgenticProd_Data.PriceTable (Model) VALUES ('role-probe')")
		Try {
			Set ^AgenticProd.Test.RoleProbe(tKey) = ##class(%SQL.Statement).%ExecDirect(, tSql).%SQLCODE
		} Catch ex {
			Set ^AgenticProd.Test.RoleProbe(tKey) = "exception: "_ex.DisplayString()
		}
	}
	Try {
		Set tTools = ##class(AgenticProd.Tools.Mapping).%New()
		Set ^AgenticProd.Test.RoleProbe("search") = tTools.SearchLoinc("Glucose", "serum", "mg/dL")
		Set ^AgenticProd.Test.RoleProbe("lookup") = tTools.LookupCode("NA-S", "LAB_SIM")
	} Catch ex {
		Set ^AgenticProd.Test.RoleProbe("search") = "exception: "_ex.DisplayString()
	}
	Set ^AgenticProd.Test.RoleProbe("done") = 1
}

Method OnAfterAllTests() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.Usage WHERE HeaderId = -9103")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.PriceTable WHERE Model = 'role-probe'")
	Kill ^AgenticProd.Test.RoleProbe
	Quit $$$OK
}

}
