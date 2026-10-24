/// Seeding and one-time configuration. Safe to run again: everything is create-or-update.
Class AgenticProd.Setup
{

/// Role and user the agent operation job switches to (Operation.Agent RunAsUser).
Parameter AGENTROLE = "AgenticProd_Agent";

Parameter AGENTUSER = "agentic_agent";

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
/// "long_name | component | system | scale | units". ReindexDocument keys each row by its LOINC
/// code, so running this again replaces rows instead of adding copies.
ClassMethod BuildLoincKB(Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = $$$OK
	Try {
		Set tEmb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
		Set tVS = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set tVS.TableName = ##class(AgenticProd.Tools.Mapping).#LOINCTABLE
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
			Continue:$LISTLENGTH(tRow)<6
			Set $LISTBUILD(tLoinc, tName, tComponent, tSystem, tScale, tUnits) = tRow
			Do tKB.ReindexDocument(tLoinc, tName_" | "_tComponent_" | "_tSystem_" | "_tScale_" | "_tUnits, {"loinc":(tLoinc), "system":(tSystem), "units":(tUnits)})
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
