/// Demo sender: file copy and MSH-10 rewrite only. Writes to a scratch folder, never data/in,
/// so nothing reaches the production or the agent. Reset is tested on stub rows only.
Class AgenticProd.Test.DemoTest Extends AgenticProd.Test.Case
{

Property Dir As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Dir = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_"Temp/demotest"_$JOB)
	Do ##class(%File).RemoveDirectoryTree(..Dir)
	Quit ##class(%File).CreateDirectoryChain(..Dir)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..Dir)
	Quit $$$OK
}

Method TestSendCaseCopies()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Demo).SendCase("01", , ..Dir, .tFile))
	Do $$$AssertEquals(##class(%File).GetFilename(tFile), "01-unmapped-glucose.hl7")
	Do $$$AssertEquals(..Text(tFile), ..Text(##class(AgenticProd.Demo).CaseFile("01")), "byte for byte")
	Do $$$AssertNotTrue(##class(%File).Exists(tFile_".tmp"), "no .tmp left")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Demo).SendCase("99", , ..Dir), "unknown case")
	Do $$$AssertStatusNotOK(##class(AgenticProd.Demo).SendCase("*", , ..Dir), "no wildcards")
}

Method TestSendCaseNewControlId()
{
	Set tOriginal = ..Text(##class(AgenticProd.Demo).CaseFile("01"))
	Do $$$AssertStatusOK(##class(AgenticProd.Demo).SendCase("01", "MSG90001", ..Dir, .tFile))
	Do $$$AssertEquals(##class(%File).GetFilename(tFile), "01-unmapped-glucose_MSG90001.hl7")
	Set tText = ..Text(tFile)
	Set tFirst = $PIECE($TRANSLATE(tOriginal, $CHAR(10), $CHAR(13)), $CHAR(13))
	Do $$$AssertEquals($PIECE($PIECE(tText, $CHAR(13)), "|", 10), "MSG90001", "MSH-10")
	Do $$$AssertNotEquals($PIECE(tFirst, "|", 10), "MSG90001", "case file had another MSH-10")
	// Everything except MSH-10 unchanged
	Do $$$AssertEquals($LENGTH(tText) - $LENGTH(tOriginal), $LENGTH("MSG90001") - $LENGTH($PIECE(tFirst, "|", 10)))
	Do $$$AssertEquals($PIECE(tText, $CHAR(13), 2, *), $PIECE(tOriginal, $CHAR(13), 2, *), "other segments")
}

Method TestSetControlId()
{
	Set tMsg = "MSH|^~\&|A|B|C|D|202610231015||ORU^R01^ORU_R01|MSG1|P|2.5.1"_$CHAR(13)_"PID|1||X"
	Do $$$AssertEquals(##class(AgenticProd.Demo).SetControlId(tMsg, "MSG2"), "MSH|^~\&|A|B|C|D|202610231015||ORU^R01^ORU_R01|MSG2|P|2.5.1"_$CHAR(13)_"PID|1||X")
	Do $$$AssertEquals(##class(AgenticProd.Demo).SetControlId($TRANSLATE(tMsg, $CHAR(13), $CHAR(10)), "MSG2"), "MSH|^~\&|A|B|C|D|202610231015||ORU^R01^ORU_R01|MSG2|P|2.5.1"_$CHAR(10)_"PID|1||X", "LF terminators")
	Do $$$AssertEquals(##class(AgenticProd.Demo).SetControlId("PID|1", "MSG2"), "PID|1", "not HL7: unchanged")
}

Method TestSendBatch()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Demo).SendBatch("01, 05,20", ..Dir))
	For tName = "01-unmapped-glucose.hl7", "05-bad-ts-obx14.hl7", "20-valid-control.hl7" {
		Do $$$AssertTrue(##class(%File).Exists(..Dir_tName), tName)
	}
	Do $$$AssertStatusNotOK(##class(AgenticProd.Demo).SendBatch("02,99,03", ..Dir), "stops at 99")
	Do $$$AssertNotTrue(##class(%File).Exists(..Dir_"03-unmapped-creatinine.hl7"), "03 not sent")
}

/// Reset on stub rows only (HeaderId < 0): live rows and their task go, eval rows and a recorded
/// live run (Usage with a CaseId) with its tool calls stay.
Method TestResetDeletesLiveOnly()
{
	Do ..RemoveStubs()
	Set tRun = -7900
	Do ..Log(-7001, "", "ESCALATE"), ..Log(-7002, tRun, "MAP_CODE")
	Do ..Usage(-7001, "", "", "stub-reset-live"), ..Usage(-7002, tRun, "01", "stub-reset-eval"), ..Usage(-7003, "", "01", "stub-reset-rec")
	For tS = "stub-reset-live", "stub-reset-eval", "stub-reset-rec" {
		Set tCall = ##class(AgenticProd.Data.ToolCall).%New()
		Set tCall.HeaderId = $CASE(tS, "stub-reset-live": -7001, "stub-reset-eval": -7002, : -7003), tCall.AgentSessionId = tS, tCall.Tool = "lookup_code", tCall.Status = "OK"
		Do $$$AssertStatusOK(tCall.%Save())
	}
	For tEval = "", tRun {
		Set tSpan = ##class(AgenticProd.Data.Span).%New()
		Set tSpan.TraceId = "stubreset"_$TRANSLATE(tEval, "-"), tSpan.SpanId = "s1", tSpan.Name = "router check", tSpan.HeaderId = $SELECT(tEval = "": -7001, 1: -7002), tSpan.EvalRunId = tEval
		Do $$$AssertStatusOK(tSpan.%Save())
		Set tSaved = ##class(AgenticProd.Data.SavedCall).%New()
		Set tSaved.HeaderId = $SELECT(tEval = "": -7001, 1: -7002), tSaved.EvalRunId = tEval
		Do $$$AssertStatusOK(tSaved.%Save())
	}
	Set tFHIR = ##class(AgenticProd.Msg.FHIRResult).%New()
	Set tFHIR.ControlId = "STUB-RESET", tFHIR.Valid = 1
	Do $$$AssertStatusOK(tFHIR.%Save())
	Set tTask = ##class(AgenticProd.Msg.ApprovalTask).%New()
	Set tTask.HeaderId = -7001, tTask.Decision = "ESCALATE", tTask.ErrorClass = "OTHER"
	Do $$$AssertStatusOK(tTask.%Save())
	Set tResp = ##class(EnsLib.Workflow.TaskResponse).%New()
	Set tRole = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("IntegrationSupport")
	Set tResp.%TaskStatus.Request = tTask, tResp.%TaskStatus.Role = tRole, tResp.%RoleName = "IntegrationSupport"
	Do $$$AssertStatusOK(tResp.%Save())
	Set tItem = ##class(EnsLib.Workflow.Worklist).%New()
	Set tItem.User = ##class(EnsLib.Workflow.UserDefinition).%OpenId("reviewer"), tItem.Role = tRole, tItem.Task = tResp
	Do $$$AssertStatusOK(tItem.%Save())

	Do $$$AssertStatusOK(##class(AgenticProd.Demo).DeleteLiveRows(1, .tCount))
	Do $$$AssertEquals(tCount("workflow tasks"), 1)
	Do $$$AssertNotTrue(##class(EnsLib.Workflow.TaskResponse).%ExistsId(tResp.%Id()), "task gone")
	Do $$$AssertNotTrue(##class(EnsLib.Workflow.Worklist).%ExistsId(tItem.%Id()), "worklist entry gone")
	Do $$$AssertEquals(..Count("DecisionLog", "HeaderId IN (-7001, -7002)"), 1, "eval DecisionLog kept")
	Do $$$AssertEquals(..Count("Usage", "HeaderId IN (-7001, -7002, -7003)"), 2, "eval and recorded Usage kept")
	Do $$$AssertEquals(..Count("ToolCall", "AgentSessionId %STARTSWITH 'stub-reset'"), 2, "tool calls of kept sessions kept")
	Do $$$AssertEquals(..Count("ToolCall", "AgentSessionId = 'stub-reset-live'"), 0)
	Do $$$AssertEquals(..Count("Span", "TraceId %STARTSWITH 'stubreset'"), 1, "eval span kept")
	Do $$$AssertEquals(..Count("SavedCall", "HeaderId IN (-7001, -7002)"), 1, "eval SavedCall kept")
	Do $$$AssertNotTrue(##class(AgenticProd.Msg.FHIRResult).%ExistsId(tFHIR.%Id()), "live FHIRResult gone")

	Do ..RemoveStubs()
}

/// Also run first, so rows left by an aborted run do not skew the counts.
Method RemoveStubs()
{
	For tTable = "DecisionLog", "Usage", "ToolCall", "Span", "SavedCall" {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data."_tTable_" WHERE HeaderId BETWEEN -7003 AND -7001")
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Msg.FHIRResult WHERE ControlId = 'STUB-RESET'")
}

/// ClearFolders empties a folder but keeps .gitkeep.
Method TestClearFolders()
{
	For tName = ".gitkeep", "a.hl7", "b.json" {
		Set tF = ##class(%Stream.FileCharacter).%New()
		Do tF.LinkToFile(..Dir_tName), tF.Write("x"), tF.%Save()
		Kill tF
	}
	Do $$$AssertEquals(##class(AgenticProd.Demo).ClearFolders(..Dir), 2)
	Do $$$AssertTrue(##class(%File).Exists(..Dir_".gitkeep"))
	Do $$$AssertNotTrue(##class(%File).Exists(..Dir_"a.hl7"))
}

Method Log(pHeaderId As %Integer, pRunId As %String, pDecision As %String)
{
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = pHeaderId, tLog.EvalRunId = pRunId, tLog.Decision = pDecision, tLog.ErrorClass = "OTHER"
	Do $$$AssertStatusOK(tLog.%Save())
}

Method Usage(pHeaderId As %Integer, pRunId As %String, pCaseId As %String, pSession As %String)
{
	Set tUsage = ##class(AgenticProd.Data.Usage).%New()
	Set tUsage.HeaderId = pHeaderId, tUsage.EvalRunId = pRunId, tUsage.CaseId = pCaseId, tUsage.AgentSessionId = pSession
	Do $$$AssertStatusOK(tUsage.%Save())
}

Method Count(pTable As %String, pWhere As %String) As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data."_pTable_" WHERE "_pWhere)
	Do tRS.%Next()
	Quit tRS.N
}

Method Text(pFile As %String) As %String
{
	Set tStream = ##class(%Stream.FileBinary).%New()
	Do tStream.LinkToFile(pFile)
	Quit tStream.Read($$$MaxStringLength)
}

}
