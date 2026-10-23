/// Tools.HL7 against eval cases 05, 08, 11, 13. Each case is saved as an HL7 message with a
/// synthetic header so the tools run the same lookup path as in the production. No LLM.
Class AgenticProd.Test.Tools.HL7Test Extends %UnitTest.TestCase
{

Parameter CASEDIR = "/home/irisowner/dev/eval/cases/";

/// Marks the headers these tests create, so cleanup finds them.
Parameter TESTSOURCE = "AgenticProd.Test.Tools";

Method TestValidateFixPassesFor05And08()
{
	For tCase = "05", "08" {
		Do $$$AssertStatusOK(..LoadCase(tCase, .tHeaderId, .tExpected), "load case "_tCase)
		Set tResult = ..Validate(tHeaderId, tExpected.fix.%ToJSON())
		Do $$$AssertEquals(tResult.result, "PASS", "case "_tCase_" expected fix passes: "_tResult.errors.%ToJSON())
		Do $$$AssertEquals(tResult.applied, tExpected.fix.%Size())
	}
}

Method TestValidateFixNeverSaves()
{
	Do $$$AssertStatusOK(..LoadCase("05", .tHeaderId, .tExpected))
	Set tResult = ..Validate(tHeaderId, tExpected.fix.%ToJSON())
	Do $$$AssertEquals(tResult.result, "PASS")
	Do ##class(AgenticProd.Tools.Base).OpenBody(tHeaderId, .tMsg)
	Do $$$AssertEquals(tMsg.GetValueAt("4:14"), "2026-10-23 10:15", "stored message unchanged")
}

Method TestValidateFixRefusesIdentity11()
{
	Do $$$AssertStatusOK(..LoadCase("11", .tHeaderId))
	Set tResult = ..Validate(tHeaderId, "[{""path"":""PID(1):3.4"",""from"":"""",""to"":""SIMHOSP""}]")
	Do $$$AssertEquals(tResult.result, "REFUSED")
	Do $$$AssertEquals(tResult.applied, 0)
	Do $$$AssertTrue(tResult.errors.%Get(0) [ "IDENTITY_ISSUE")
	// Any PID-5 or PID-7 step refuses the whole fix, even next to a valid step
	Set tResult = ..Validate(tHeaderId, "[{""path"":""OBX(1):11"",""to"":""F""},{""path"":""PID:7"",""to"":""19850215""}]")
	Do $$$AssertEquals(tResult.result, "REFUSED")
}

Method TestValidateFixFails13()
{
	Do $$$AssertStatusOK(..LoadCase("13", .tHeaderId))
	// A valid field change cannot fix segment order, so validation must still fail
	Set tResult = ..Validate(tHeaderId, "[{""path"":""OBX(1):14"",""from"":""20261023101500"",""to"":""202610231015""}]")
	Do $$$AssertEquals(tResult.result, "FAIL")
	Do $$$AssertEquals(tResult.applied, 1)
	Do $$$AssertTrue(tResult.errors.%ToJSON() [ "OBR", "structure error names the missing OBR: "_tResult.errors.%ToJSON())
}

Method TestValidateFixStaleFromFails()
{
	Do $$$AssertStatusOK(..LoadCase("05", .tHeaderId))
	Set tResult = ..Validate(tHeaderId, "[{""path"":""OBX(1):14"",""from"":""wrong"",""to"":""202610231015""}]")
	Do $$$AssertEquals(tResult.result, "FAIL")
	Do $$$AssertEquals(tResult.applied, 0)
	Set tResult = ..Validate(tHeaderId, "not json")
	Do $$$AssertEquals(tResult.result, "FAIL")
}

Method TestGetSegmentMasksPid()
{
	Do $$$AssertStatusOK(..LoadCase("05", .tHeaderId))
	Set tTools = ##class(AgenticProd.Tools.HL7).%New()
	Set tOut = tTools.GetSegment(tHeaderId, "OBX(1)")
	Do $$$AssertTrue(tOut [ "<untrusted_data", "wrapped as untrusted")
	Do $$$AssertTrue(tOut [ ("OBX-14=2026-10-23 10:15"), "numbered field")
	Set tOut = tTools.GetSegment(tHeaderId, "PID")
	Do $$$AssertNotTrue(tOut [ "TESTPATIENT", "name masked")
	Do $$$AssertNotTrue(tOut [ "19850214", "birth date masked")
	Do $$$AssertTrue(tOut [ "PID-3=100001^^^SIMHOSP^MR", "identifier shown")
	Do $$$AssertTrue(tTools.GetSegment(tHeaderId, "OBX(2)") [ "ERROR", "missing occurrence")
}

Method TestSearchInterfaceSpec()
{
	Set tTools = ##class(AgenticProd.Tools.HL7).%New()
	Set tOut = tTools.SearchInterfaceSpec("0123")
	Do $$$AssertTrue(tOut [ "OBR-25", "table 0123 section")
	Do $$$AssertNotTrue(tOut [ "## TS", "only matching sections")
	Do $$$AssertTrue(tTools.SearchInterfaceSpec("pid-3") [ "PID-3.4")
	Do $$$AssertTrue(tTools.SearchInterfaceSpec("nothing-like-this") [ "Full spec")
}

/// Call the validate_fix tool method and parse the JSON out of its untrusted_data block.
Method Validate(pHeaderId As %Integer, pFixJSON As %String) As %DynamicObject
{
	Set tOut = ##class(AgenticProd.Tools.HL7).%New().ValidateFix(pHeaderId, pFixJSON)
	If $EXTRACT(tOut) = "<" Set tOut = $PIECE(tOut, $CHAR(10), 2, $LENGTH(tOut, $CHAR(10)) - 1)
	Quit {}.%FromJSON(tOut)
}

/// Save eval case pCaseId as an HL7 message behind a synthetic header. pExpected is its
/// .expected.json. Cleanup deletes everything with TESTSOURCE as the header source.
ClassMethod LoadCase(pCaseId As %String, Output pHeaderId As %Integer, Output pExpected As %DynamicObject) As %Status
{
	Set pHeaderId = "", pExpected = ""
	Set tSC = $$$OK
	Try {
		Set tFile = $ZSEARCH(..#CASEDIR_pCaseId_"-*.hl7")
		If tFile = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "No eval case "_pCaseId_" in "_..#CASEDIR))
		Set tStream = ##class(%Stream.FileCharacter).%New()
		$$$ThrowOnError(tStream.LinkToFile(tFile))
		Set tText = $REPLACE($REPLACE(tStream.Read(1000000), $CHAR(13,10), $CHAR(13)), $CHAR(10), $CHAR(13))
		Set tMsg = ##class(EnsLib.HL7.Message).ImportFromString(tText, .tSC)
		$$$ThrowOnError(tSC)
		$$$ThrowOnError(tMsg.%Save())

		Set tHeader = ##class(Ens.MessageHeader).%New()
		Set tHeader.SourceConfigName = ..#TESTSOURCE
		Set tHeader.MessageBodyClassName = "EnsLib.HL7.Message"
		Set tHeader.MessageBodyId = tMsg.%Id()
		$$$ThrowOnError(tHeader.%Save())
		Set tHeader.SessionId = tHeader.%Id()
		$$$ThrowOnError(tHeader.%Save())
		Set pHeaderId = tHeader.%Id()

		Set tJsonFile = $PIECE(tFile, ".hl7")_".expected.json"
		Set tStream = ##class(%Stream.FileCharacter).%New()
		$$$ThrowOnError(tStream.LinkToFile(tJsonFile))
		Set pExpected = {}.%FromJSON(tStream)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod Cleanup() As %Status
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyId FROM Ens.MessageHeader WHERE SourceConfigName = ?", ..#TESTSOURCE)
	While tRS.%Next() {
		Do ##class(EnsLib.HL7.Message).%DeleteId(tRS.MessageBodyId)
		Do ##class(Ens.MessageHeader).%DeleteId(tRS.ID)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ConfigName = ?", ..#TESTSOURCE)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Quit ..Cleanup()
}

}
