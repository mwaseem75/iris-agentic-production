/// LabRouter checks and the DTL on eval cases, called directly (no production, no LLM).
Class AgenticProd.Test.Process.LabRouterTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(AgenticProd.Setup).SeedLabCodeMap()
}

Method TestValidControl20()
{
	Do ..CheckCase("20", .tClass, .tText, .tMsg)
	Do $$$AssertEquals(tClass, "", "valid control needs no triage: "_tText)
	Do $$$AssertStatusOK(##class(AgenticProd.DTL.LabToNphies).Transform(tMsg, .tOut))
	Do $$$AssertEquals(tOut.GetValueAt("4:3"), "2951-2^Sodium [Moles/volume] in Serum or Plasma^LN", "OBX-3 mapped to LOINC")
	Do $$$AssertEquals(tMsg.GetValueAt("4:3"), "NA-S^Sodium^L", "source unchanged")
}

Method TestErrorClasses()
{
	For tCase = "01:UNMAPPED_CODE", "05:BAD_FORMAT", "13:STRUCTURE_ERROR", "14:ROUTING" {
		Do ..CheckCase($PIECE(tCase, ":"), .tClass, .tText)
		Do $$$AssertEquals(tClass, $PIECE(tCase, ":", 2), "case "_tCase_": "_tText)
	}
	Do ..CheckCase("01", .tClass, .tText)
	Do $$$AssertEquals(tText, "Lookup LabCodeMap: no entry for OBX(1):3.1 'GLU-01' from LAB_SIM")
	// 05 uses a seeded code, so the bad TS is its only problem
	Do ..CheckCase("05", .tClass, .tText)
	Do $$$AssertNotTrue(tText [ "Lookup", tText)
	// 16 has a bad TS and the unmapped ALT-S: both are listed, the class is the first by CLASSORDER
	Do ..CheckCase("16", .tClass, .tText)
	Do $$$AssertEquals(tClass, "BAD_FORMAT")
	Do $$$AssertTrue((tText [ "OBX(1):14") && (tText [ "'ALT-S'"), tText)
}

Method CheckCase(pCaseId As %String, Output pClass As %String, Output pText As %String, Output pMsg As EnsLib.HL7.Message)
{
	Do $$$AssertStatusOK(##class(AgenticProd.Test.Tools.HL7Test).LoadCase(pCaseId, .tHeaderId))
	Do ##class(AgenticProd.Tools.Base).OpenBody(tHeaderId, .pMsg)
	Do $$$AssertStatusOK(##class(AgenticProd.Process.LabRouter).Check(pMsg, .pClass, .pText))
}

Method OnAfterAllTests() As %Status
{
	Quit ##class(AgenticProd.Test.Tools.HL7Test).Cleanup()
}

}
