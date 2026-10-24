/// Demo sender: file copy and MSH-10 rewrite only. Writes to a scratch folder, never data/in,
/// so nothing reaches the production or the agent.
Class AgenticProd.Test.DemoTest Extends %UnitTest.TestCase
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

Method Text(pFile As %String) As %String
{
	Set tStream = ##class(%Stream.FileBinary).%New()
	Do tStream.LinkToFile(pFile)
	Quit tStream.Read($$$MaxStringLength)
}

}
