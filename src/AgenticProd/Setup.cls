/// Seeding and one-time configuration. Safe to run again: everything is create-or-update.
Class AgenticProd.Setup
{

/// Role and user the agent operation job switches to (Operation.Agent RunAsUser).
Parameter AGENTROLE = "AgenticProd_Agent";

Parameter AGENTUSER = "agentic_agent";

/// Workflow role; also the name of the EnsLib.Workflow.Operation item Triage sends tasks to.
Parameter REVIEWROLE = "IntegrationSupport";

/// Demo reviewer for the Workflow inbox. Demo-only password, documented in the README.
Parameter REVIEWUSER = "reviewer";

Parameter REVIEWPASSWORD = "Review-Demo-2026";

/// Dashboard: DASHAPP serves web/ (login form, then the page), DASHAPI is UI.REST. Both need
/// DASHRESOURCE, held by DASHROLE (given to the reviewer) and by %All, so only the reviewer
/// and SuperUser get in. The page app does the login because %CSP.REST sends its challenge from
/// Login(), which runs as UnknownUser and cannot load a class from IRISAPP.
Parameter DASHAPP = "/agenticprod";

Parameter DASHAPI = "/agenticprod/api";

/// Vendored chart library (web/vendor), served under the page app's login.
Parameter DASHVENDOR = "/agenticprod/vendor";

Parameter DASHDIR = "/home/irisowner/dev/web/";

/// Login group shared by DASHAPP and DASHAPI, so one login covers the page and its API calls.
Parameter DASHGROUP = "AgenticProd";

Parameter DASHRESOURCE = "AgenticProd_Dashboard";

Parameter DASHROLE = "AgenticProd_Dashboard";

/// Read-only databases: the dashboard never writes. IRISTEMP is RW for SQL work globals.
Parameter DASHRESOURCES = "AgenticProd_Dashboard:U,%DB_IRISAPP_DATA:R,%DB_IRISAPP_CODE:R,%DB_ENSLIB:R,%DB_HSLIB:R,%DB_HSSYS:R,%DB_IRISLIB:R,%DB_IRISSYS:R,%DB_IRISTEMP:RW";

/// Role added to /api/monitor so Monitor.Metrics can run in IRISAPP (Setup.MonitorSetup).
Parameter MONITORROLE = "AgenticProd_Monitor";

Parameter MONITORRESOURCES = "%DB_IRISAPP_DATA:R,%DB_IRISAPP_CODE:R,%DB_ENSLIB:R,%DB_IRISLIB:R";

/// Synthetic-use LOINC subset (see kb/LOINC_NOTICE.md).
Parameter LOINCFILE = "/home/irisowner/dev/kb/loinc_subset.csv";

/// Database resources only cover what an interop job needs to store messages and read code.
/// Data access inside IRISAPP_DATA is still all-or-nothing for globals; SQL grants narrow it
/// for %SQL.Statement, which is the only way agent tools may query.
Parameter AGENTRESOURCES = "%DB_IRISAPP_DATA:RW,%DB_IRISAPP_CODE:R,%DB_ENSLIB:R,%DB_HSLIB:R,%DB_HSSYS:R,%DB_IRISLIB:R,%DB_IRISSYS:R,%DB_IRISTEMP:RW";

ClassMethod Run() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(##class(AgenticProd.Data.PriceTable).Seed())
		$$$ThrowOnError(..SeedLabCodeMap())
		$$$ThrowOnError(..BuildLoincKB())
		$$$ThrowOnError(..AgentSecurity())
		$$$ThrowOnError(..WorkflowSetup())
		$$$ThrowOnError(..DashboardSetup())
		$$$ThrowOnError(..MonitorSetup())
		// Setup runs at image build with IRIS about to stop, so starting it here would not last
		$$$ThrowOnError(##class(Ens.Director).SetAutoStart("AgenticProd.Production"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// LabCodeMap lookup: local code -> "LOINC^display" (DTL.LabToNphies appends ^LN).
/// Exactly the seed table in eval/cases/README.md; the eval cases' other codes (GLU-01,
/// CREA-S, ...) must stay unmapped so they reach the agent as UNMAPPED_CODE.
ClassMethod SeedLabCodeMap() As %Status
{
	Set tSC = $$$OK
	For tRow = $LISTBUILD("NA-S", "2951-2", "Sodium [Moles/volume] in Serum or Plasma"),
		$LISTBUILD("CL-S", "2075-0", "Chloride [Moles/volume] in Serum or Plasma"),
		$LISTBUILD("CA-S", "17861-6", "Calcium [Mass/volume] in Serum or Plasma"),
		$LISTBUILD("UA-S", "3084-1", "Urate [Mass/volume] in Serum or Plasma"),
		$LISTBUILD("TSH", "3016-3", "Thyrotropin [Units/volume] in Serum or Plasma"),
		$LISTBUILD("CRP-S", "1988-5", "C reactive protein [Mass/volume] in Serum or Plasma"),
		$LISTBUILD("CULT-U", "630-4", "Bacteria identified in Urine by Culture") {
		Set tSC = ##class(Ens.Util.LookupTable).%UpdateValue("LabCodeMap", $LIST(tRow, 1), $LIST(tRow, 2)_"^"_$LIST(tRow, 3))
		Quit:$$$ISERR(tSC)
	}
	Quit tSC
}

/// Knowledge base search_loinc: one FastEmbed (local) vector row per line of LOINCFILE, text
/// "long_name | component | system | scale | method | units" (method "none" when empty).
/// ReindexDocument keys each row by its LOINC code, so running this again replaces rows instead
/// of adding copies. A table missing a promoted field is dropped and built again.
ClassMethod BuildLoincKB(Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = $$$OK
	Try {
		Set tTable = ##class(AgenticProd.Tools.Mapping).#LOINCTABLE
		// build 154: VectorStore.Build is CREATE TABLE IF NOT EXISTS, it never adds a new column
		Set tIter = ##class(AgenticProd.Tools.Mapping).LoincFields().%GetIterator()
		While tIter.%GetNext(, .tField) {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?", $PIECE(tTable, "."), $PIECE(tTable, ".", 2), tField.name)
			Continue:tRS.%Next()
			For tDrop = tTable, tTable_"_Config" {
				Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE IF EXISTS "_tDrop)
				If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
			}
			Quit
		}
		Set tEmb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
		Set tVS = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set tVS.TableName = tTable
		Set tVS.Dimensions = tEmb.Dimensions
		Set tVS.ModelName = tEmb.ModelName
		// Promoted so search_loinc returns them as fields, not parsed out of the text
		$$$ThrowOnError(tVS.Build(##class(AgenticProd.Tools.Mapping).LoincFields()))
		Set tKB = ##class(%AI.RAG.KnowledgeBase).%New("search_loinc", "LOINC subset for lab code mapping")
		$$$ThrowOnError(tKB.Build(tEmb, tVS))

		Set tFile = ##class(%Stream.FileCharacter).%New()
		$$$ThrowOnError(tFile.LinkToFile(..#LOINCFILE))
		Do tFile.ReadLine()
		While 'tFile.AtEnd {
			Set tLine = $ZSTRIP(tFile.ReadLine(), ">", $CHAR(13))
			Continue:tLine=""
			Set tRow = ..CSVRow(tLine)
			Continue:$LISTLENGTH(tRow)<7
			Set $LISTBUILD(tLoinc, tName, tComponent, tSystem, tScale, tMethod, tUnits) = tRow
			Do tKB.ReindexDocument(tLoinc, tName_" | "_tComponent_" | "_tSystem_" | "_tScale_" | "_$SELECT(tMethod'="": tMethod, 1: "none")_" | "_tUnits, {"loinc":(tLoinc), "system":(tSystem), "method":(tMethod), "units":(tUnits)})
			Set pCount = pCount + 1
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// One CSV line as a $LIST; double-quoted fields may hold commas and "" for a quote.
ClassMethod CSVRow(pLine As %String) As %List [ Internal ]
{
	Set tRow = "", tField = "", tQuoted = 0
	For i = 1:1:$LENGTH(pLine) {
		Set c = $EXTRACT(pLine, i)
		If tQuoted {
			If c '= """" { Set tField = tField_c }
			ElseIf $EXTRACT(pLine, i + 1) = """" { Set tField = tField_"""", i = i + 1 }
			Else { Set tQuoted = 0 }
		} ElseIf c = """" {
			Set tQuoted = 1
		} ElseIf c = "," {
			Set tRow = tRow_$LISTBUILD(tField), tField = ""
		} Else {
			Set tField = tField_c
		}
	}
	Quit tRow_$LISTBUILD(tField)
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
			"GRANT SELECT ON SCHEMA AgenticProd_KB TO "_..#AGENTROLE,
			"GRANT INSERT ON AgenticProd_Data.ToolCall, AgenticProd_Data.Usage, AgenticProd_Data.DecisionLog TO "_..#AGENTROLE {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSql)
			If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message_" ("_tSql_")"))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Workflow role REVIEWROLE with the demo reviewer in it. The reviewer is an IRIS user with
/// %EnsRole_Operator only, enough for the Workflow inbox.
ClassMethod WorkflowSetup() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CreateReviewer($NAMESPACE))
		If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(..#REVIEWROLE) {
			$$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).CreateRole(..#REVIEWROLE))
		}
		If '##class(EnsLib.Workflow.UserDefinition).%ExistsId(..#REVIEWUSER) {
			$$$ThrowOnError(##class(EnsLib.Workflow.UserDefinition).CreateUser(..#REVIEWUSER, "Demo reviewer"))
		}
		If '##class(EnsLib.Workflow.RoleMembership).%ExistsId(..#REVIEWROLE_"||"_..#REVIEWUSER) {
			$$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(..#REVIEWROLE, ..#REVIEWUSER))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Web apps DASHAPP and DASHAPI, their resource and role, the reviewer in that role, and
/// SELECT on the tables UI.REST reads. Needs WorkflowSetup first (the reviewer user).
ClassMethod DashboardSetup() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CreateDashboardApp($NAMESPACE))
		Set tSql = "GRANT SELECT ON AgenticProd_Data.DecisionLog, AgenticProd_Data.Usage, AgenticProd_Data.EvalRun, AgenticProd_Data.EvalResult, AgenticProd_Data.ToolCall, AgenticProd_Data.Span, AgenticProd_Data.SavedCall, AgenticProd_Msg.ApprovalTask, AgenticProd_Msg.FHIRResult, AgenticProd_Msg.TriageRequest, Ens.MessageHeader, EnsLib_Workflow.TaskResponse TO "_..#DASHROLE
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSql)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message_" ("_tSql_")"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Register Monitor.Metrics and Monitor.GenAI with SAM, so /api/monitor/metrics carries the agentic metrics, and
/// give that app MONITORROLE: /api/monitor runs as UnknownUser with %DB_IRISSYS only, so it could
/// not load the class or read IRISAPP. The role reads the databases and SELECTs the tables the
/// metrics count; the endpoint shows counts only, no message data.
ClassMethod MonitorSetup() As %Status
{
	Set tSC = $$$OK
	Try {
		Set tNamespace = $NAMESPACE
		New $NAMESPACE
		Set $NAMESPACE = "%SYS"
		Set tDesc = "AgenticProd metrics for /api/monitor: read-only counts"
		If ##class(Security.Roles).Exists(..#MONITORROLE) {
			Set tProps("Description") = tDesc, tProps("Resources") = ..#MONITORRESOURCES
			$$$ThrowOnError(##class(Security.Roles).Modify(..#MONITORROLE, .tProps))
		} Else {
			$$$ThrowOnError(##class(Security.Roles).Create(..#MONITORROLE, tDesc, ..#MONITORRESOURCES))
		}
		$$$ThrowOnError(##class(Security.Applications).Get("/api/monitor", .tApp))
		// MatchRoles is ":role" (always granted) or "match:role", pieces after the first
		If (tApp("MatchRoles")_":") '[ (":"_..#MONITORROLE_":") {
			Kill tProps
			Set tProps("MatchRoles") = tApp("MatchRoles")_":"_..#MONITORROLE
			$$$ThrowOnError(##class(Security.Applications).Modify("/api/monitor", .tProps))
		}
		For tClass = "AgenticProd.Monitor.Metrics", "AgenticProd.Monitor.GenAI" {
			$$$ThrowOnError(##class(SYS.Monitor.SAM.Config).AddApplicationClass(tClass, tNamespace))
		}
		Set $NAMESPACE = tNamespace
		Set tSql = "GRANT SELECT ON AgenticProd_Data.DecisionLog, AgenticProd_Data.Usage, AgenticProd_Data.ToolCall, AgenticProd_Data.SavedCall, AgenticProd_Msg.ApprovalTask, EnsLib_Workflow.TaskResponse TO "_..#MONITORROLE
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSql)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message_" ("_tSql_")"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod CreateDashboardApp(pNamespace As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set tSC = $$$OK
	Try {
		// No public permission: holding the resource is the whole access check
		If '##class(Security.Resources).Exists(..#DASHRESOURCE) {
			$$$ThrowOnError(##class(Security.Resources).Create(..#DASHRESOURCE, "AgenticProd dashboard", ""))
		}
		Set tDesc = "AgenticProd dashboard: read-only"
		If ##class(Security.Roles).Exists(..#DASHROLE) {
			Set tProps("Description") = tDesc, tProps("Resources") = ..#DASHRESOURCES
			$$$ThrowOnError(##class(Security.Roles).Modify(..#DASHROLE, .tProps))
		} Else {
			$$$ThrowOnError(##class(Security.Roles).Create(..#DASHROLE, tDesc, ..#DASHRESOURCES))
		}
		$$$ThrowOnError(..AddUserRole(..#REVIEWUSER, ..#DASHROLE))
		For tApp = ..#DASHAPP, ..#DASHAPI, ..#DASHVENDOR {
			Kill tProps
			Set tProps("NameSpace") = pNamespace
			Set tProps("Resource") = ..#DASHRESOURCE
			// 32 = password only
			Set tProps("AutheEnabled") = 32
			Set tProps("GroupById") = ..#DASHGROUP
			Set tProps("Enabled") = 1
			If tApp = ..#DASHAPP {
				Set tProps("Description") = "AgenticProd dashboard page"
				Set tProps("DispatchClass") = "", tProps("Path") = ..#DASHDIR, tProps("ServeFiles") = 3
				// ServeFiles 3: static files go through the login and resource check (1 serves them to anyone)
				// Recurse off, or /agenticprod/api would be served from DASHDIR too
				Set tProps("Recurse") = 0
			} ElseIf tApp = ..#DASHVENDOR {
				// Own app so the page app can keep Recurse off; same login and resource as the page
				Set tProps("Description") = "AgenticProd dashboard libraries (web/vendor)"
				Set tProps("DispatchClass") = "", tProps("Path") = ..#DASHDIR_"vendor/", tProps("ServeFiles") = 3, tProps("Recurse") = 1
			} Else {
				Set tProps("Description") = "AgenticProd dashboard API (read-only)"
				Set tProps("DispatchClass") = "AgenticProd.UI.REST"
			}
			If ##class(Security.Applications).Exists(tApp) {
				$$$ThrowOnError(##class(Security.Applications).Modify(tApp, .tProps))
			} Else {
				$$$ThrowOnError(##class(Security.Applications).Create(tApp, .tProps))
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Add pRole to pUser's roles, keeping the ones it has. Call from %SYS.
ClassMethod AddUserRole(pUser As %String, pRole As %String) As %Status [ Private ]
{
	Set tSC = ##class(Security.Users).Get(pUser, .tProps)
	Quit:$$$ISERR(tSC) tSC
	Quit:$LISTFIND($LISTFROMSTRING(tProps("Roles")), pRole) $$$OK
	Set tNew("Roles") = tProps("Roles")_$SELECT(tProps("Roles") '= "": ",", 1: "")_pRole
	Quit ##class(Security.Users).Modify(pUser, .tNew)
}

ClassMethod CreateReviewer(pNamespace As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit:##class(Security.Users).Exists(..#REVIEWUSER) $$$OK
	Quit ##class(Security.Users).Create(..#REVIEWUSER, "%EnsRole_Operator", ..#REVIEWPASSWORD, "AgenticProd demo reviewer", pNamespace)
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
