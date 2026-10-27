Include Ensemble

/// Drops eval cases into LabFileIn's folder so the production picks them up like any lab file.
/// Every case that fails the LabCodeMap lookup or validation goes to Triage, i.e. a live agent call.
/// Reset() clears live traffic for a clean demo or recording.
Class AgenticProd.Demo
{

Parameter CASEDIR = "/home/irisowner/dev/eval/cases/";

/// LabFileIn FilePath.
Parameter INDIR = "/home/irisowner/dev/data/in/";

/// Copy eval/cases/<pCase>-*.hl7 to pDir (default data/in). pControlId, when set, replaces MSH-10
/// so a case that already went through can be sent again as a new message. pFile returns the written path.
ClassMethod SendCase(pCase As %String, pControlId As %String = "", pDir As %String = {..#INDIR}, Output pFile As %String) As %Status
{
	Set tSC = $$$OK, pFile = ""
	Try {
		Set tSource = ..CaseFile(pCase)
		If tSource = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "no case file "_..#CASEDIR_pCase_"-*.hl7"))
		Set tIn = ##class(%Stream.FileBinary).%New()
		$$$ThrowOnError(tIn.LinkToFile(tSource))
		Set tText = tIn.Read($$$MaxStringLength)
		Set:pControlId'="" tText = ..SetControlId(tText, pControlId)

		Set tName = ##class(%File).GetFilename(tSource)
		Set:pControlId'="" tName = $PIECE(tName, ".hl7")_"_"_pControlId_".hl7"
		Set pFile = ##class(%File).NormalizeFilename(tName, pDir)
		// Written as .tmp and renamed: FileSpec *.hl7 must not see a half-written file
		Set tOut = ##class(%Stream.FileBinary).%New()
		$$$ThrowOnError(tOut.LinkToFile(pFile_".tmp"))
		$$$ThrowOnError(tOut.Write(tText))
		$$$ThrowOnError(tOut.%Save())
		Kill tOut
		If '##class(%File).Rename(pFile_".tmp", pFile, .tErr) $$$ThrowStatus($$$ERROR($$$GeneralError, "rename to "_pFile_" failed ("_tErr_")"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Send each case in a comma list, e.g. "01,05,20". Stops at the first failure.
ClassMethod SendBatch(pCases As %String, pDir As %String = {..#INDIR}) As %Status
{
	Set tSC = $$$OK
	For i = 1:1:$LENGTH(pCases, ",") {
		Set tCase = $ZSTRIP($PIECE(pCases, ",", i), "<>W")
		Continue:tCase=""
		Set tSC = ..SendCase(tCase, , pDir)
		Quit:$$$ISERR(tSC)
	}
	Quit tSC
}

/// Folders Reset empties (the .gitkeep files stay).
Parameter RESETDIRS = "/home/irisowner/dev/data/in/,/home/irisowner/dev/data/out/,/home/irisowner/dev/data/out-fhir/,/home/irisowner/dev/data/rejected/";

/// Clean state for a demo or a recording, without asking: deletes live (non-eval) DecisionLog,
/// Usage, ToolCall, Span, SavedCall and FHIRResult rows and their Workflow tasks, purges every
/// production message, resets LabCodeMap and LearnedMapping to the Setup seed and empties RESETDIRS. EvalRun,
/// EvalResult, eval Usage rows and the live runs replay reads (Usage rows with a CaseId) stay.
/// Writes and logs what it removed.
ClassMethod Reset() As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..DeleteLiveRows(0, .tCount))
		// Bodies too and no integrity check: the point is an empty message archive, open sessions included
		$$$ThrowOnError(##class(Ens.Purge).PurgeMessagesByDate(0, .tPurged, 0, 1))
		Set tCount("messages") = +$GET(tPurged)
		// Provenance goes with the DecisionLog rows it points at; the seed rows come back below
		Set tCount("LearnedMapping") = ..Exec("DELETE FROM AgenticProd_Data.LearnedMapping")
		Do ##class(Ens.Util.LookupTable).%ClearTable("LabCodeMap")
		$$$ThrowOnError(##class(AgenticProd.Setup).SeedLabCodeMap())
		Set tCount("files") = ..ClearFolders(..#RESETDIRS)
		Set tText = "", tKey = ""
		For {
			Set tKey = $ORDER(tCount(tKey))
			Quit:tKey=""
			Set tText = tText_$SELECT(tText '= "": ", ", 1: "")_tKey_" "_tCount(tKey)
		}
		Set tText = "Demo.Reset removed "_tText_"; LabCodeMap back to the Setup seed"
		Write tText, !
		$$$LOGINFO(tText)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Delete live rows and their Workflow tasks; pCount(table) = rows deleted. pStubOnly limits
/// every delete to test rows (HeaderId < 0, FHIRResult ControlId STUB*) so the unit test can run
/// on a database that holds real data.
ClassMethod DeleteLiveRows(pStubOnly As %Boolean, Output pCount) As %Status
{
	Set tSC = $$$OK
	Kill pCount
	Try {
		Set tStub = $SELECT(pStubOnly: " AND HeaderId < 0", 1: "")
		// Tasks first: they are found through the DecisionLog rows deleted below
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT r.ID, r.TaskStatus_Request AS TaskId FROM EnsLib_Workflow.TaskResponse r"
			_" JOIN AgenticProd_Msg.ApprovalTask t ON t.ID = r.TaskStatus_Request JOIN AgenticProd_Data.DecisionLog d ON d.HeaderId = t.HeaderId"
			_" WHERE d.EvalRunId IS NULL"_$SELECT(pStubOnly: " AND d.HeaderId < 0", 1: ""))
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		Set pCount("workflow tasks") = 0
		While tRS.%Next() {
			Do ..Exec("DELETE FROM EnsLib_Workflow.Worklist WHERE Task = ?", tRS.ID)
			$$$ThrowOnError(##class(EnsLib.Workflow.TaskResponse).%DeleteId(tRS.ID))
			Do ##class(AgenticProd.Msg.ApprovalTask).%DeleteId(tRS.TaskId)
			Set pCount("workflow tasks") = pCount("workflow tasks") + 1
		}
		Set pCount("DecisionLog") = ..Exec("DELETE FROM AgenticProd_Data.DecisionLog WHERE EvalRunId IS NULL"_tStub)
		// A live row with a CaseId is a recorded run that replay may still read
		Set pCount("Usage") = ..Exec("DELETE FROM AgenticProd_Data.Usage WHERE EvalRunId IS NULL AND (CaseId IS NULL OR CaseId = '')"_tStub)
		// ToolCall has no EvalRunId: a call goes when no remaining Usage row has its session
		Set pCount("ToolCall") = ..Exec("DELETE FROM AgenticProd_Data.ToolCall WHERE (AgentSessionId IS NULL"
			_" OR AgentSessionId NOT IN (SELECT AgentSessionId FROM AgenticProd_Data.Usage WHERE AgentSessionId IS NOT NULL))"_tStub)
		Set pCount("Span") = ..Exec("DELETE FROM AgenticProd_Data.Span WHERE EvalRunId IS NULL"_tStub)
		Set pCount("SavedCall") = ..Exec("DELETE FROM AgenticProd_Data.SavedCall WHERE EvalRunId IS NULL"_tStub)
		Set pCount("FHIRResult") = ..Exec("DELETE FROM AgenticProd_Msg.FHIRResult WHERE (ControlId IS NULL OR ControlId NOT LIKE 'EV%-%')"
			_$SELECT(pStubOnly: " AND ControlId %STARTSWITH 'STUB'", 1: ""))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Rows affected by pSQL; throws on an SQL error.
ClassMethod Exec(pSQL As %String, pArgs...) As %Integer [ Internal ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, pSQL, pArgs...)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Quit +tRS.%ROWCOUNT
}

/// Delete every file but .gitkeep in each folder of the comma list pDirs; returns how many.
ClassMethod ClearFolders(pDirs As %String) As %Integer
{
	Set tCount = 0
	For i = 1:1:$LENGTH(pDirs, ",") {
		Set tDir = $PIECE(pDirs, ",", i)
		Continue:(tDir="")||'##class(%File).DirectoryExists(tDir)
		Set tFile = $ZSEARCH(##class(%File).NormalizeDirectory(tDir)_"*")
		While tFile '= "" {
			Set tName = ##class(%File).GetFilename(tFile)
			If (tName '= ".gitkeep") && (tName '= ".") && (tName '= "..") && '##class(%File).DirectoryExists(tFile) {
				Set:##class(%File).Delete(tFile) tCount = tCount + 1
			}
			Set tFile = $ZSEARCH("")
		}
	}
	Quit tCount
}

/// Path of eval/cases/<pCase>-*.hl7, "" when there is none.
ClassMethod CaseFile(pCase As %String) As %String
{
	Quit:pCase'?1.AN ""
	Quit $ZSEARCH(..#CASEDIR_pCase_"-*.hl7")
}

/// pText with MSH-10 set to pControlId. Works on the raw bytes so the case file's segment
/// terminators and everything else stay byte for byte.
ClassMethod SetControlId(pText As %String, pControlId As %String) As %String
{
	Quit:$EXTRACT(pText, 1, 3)'="MSH" pText
	Set tFS = $EXTRACT(pText, 4)
	Set tEnd = $FIND(pText, $CHAR(13)), tLF = $FIND(pText, $CHAR(10))
	Set:'tEnd||(tLF&&(tLF<tEnd)) tEnd = tLF
	Set tMSH = $SELECT(tEnd: $EXTRACT(pText, 1, tEnd - 2), 1: pText)
	// MSH-1 is the separator itself, so MSH-10 is piece 10
	Set $PIECE(tMSH, tFS, 10) = pControlId
	Quit tMSH_$SELECT(tEnd: $EXTRACT(pText, tEnd - 1, *), 1: "")
}

}
