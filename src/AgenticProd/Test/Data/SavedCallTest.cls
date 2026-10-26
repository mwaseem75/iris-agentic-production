/// Data.SavedCall.Note: a message passing on a learned mapping counts once; the resend of the
/// approved message itself does not. No production, no LLM.
Class AgenticProd.Test.Data.SavedCallTest Extends %UnitTest.TestCase
{

Parameter CODE = "TST-SAVED-1";

Method TestLearnedCodeCounts()
{
	Set tMsg = ..Message()
	Do $$$AssertStatusOK(..Approved(-9371, ""))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.SavedCall).Note(tMsg, -9372))
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT LocalCodes, EvalRunId FROM AgenticProd_Data.SavedCall WHERE HeaderId = -9372")
	Do $$$AssertTrue(tRS.%Next(), "counted")
	Do $$$AssertEquals(tRS.LocalCodes, ..#CODE)
	Do $$$AssertEquals(tRS.EvalRunId, 77, "from MSH-10 EV77-01")
}

/// The approval resends its own failed message: same body, not a saved call, even when another
/// approval of the same code exists (eval runs approve the same code again).
Method TestApprovalResendNotCounted()
{
	Set tMsg = ..Message()
	Set tHeader = ##class(Ens.MessageHeader).%New()
	Set tHeader.MessageBodyClassName = $CLASSNAME(tMsg), tHeader.MessageBodyId = tMsg.%Id()
	Do $$$AssertStatusOK(tHeader.%Save())
	Do $$$AssertStatusOK(..Approved(tHeader.%Id(), ""))
	Do $$$AssertStatusOK(..Approved(-9373, ""))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.SavedCall).Note(tMsg, -9374))
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall WHERE HeaderId = -9374")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.N, 0, "approval's own resend")
	Do ##class(Ens.MessageHeader).%DeleteId(tHeader.%Id())
}

Method TestUnlearnedCodeNotCounted()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Data.SavedCall).Note(..Message(), -9375))
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall WHERE HeaderId = -9375")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.N, 0)
}

Method Approved(pHeader As %Integer, pRun As %String) As %Status
{
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tRow.HeaderId = pHeader, tRow.Decision = "MAP_CODE", tRow.ErrorClass = "UNMAPPED_CODE"
	Set tRow.LocalCode = ..#CODE, tRow.Loinc = "2345-7", tRow.Outcome = "APPROVED", tRow.EvalRunId = pRun
	Quit tRow.%Save()
}

/// Saved synthetic ORU^R01 with OBX-3.1 = CODE.
Method Message() As EnsLib.HL7.Message
{
	Set tText = "MSH|^~\&|LAB_SIM|SIM_HOSP|AGENTIC|NPHIES_SIM|20261023101500||ORU^R01^ORU_R01|EV77-01|P|2.5.1"_$CHAR(13)
		_"OBX|1|NM|"_..#CODE_"^Test^L||5.4|mmol/L|||||F"
	Set tMsg = ##class(EnsLib.HL7.Message).ImportFromString(tText, .tSC)
	Do $$$AssertStatusOK(tSC)
	Do $$$AssertStatusOK(tMsg.%Save())
	Set ..Saved = ..Saved_$LISTBUILD(tMsg.%Id())
	Quit tMsg
}

Property Saved As %List;

Method OnAfterOneTest() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE LocalCode = ?", ..#CODE)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.SavedCall WHERE HeaderId BETWEEN -9379 AND -9370")
	Set tPtr = 0
	While $LISTNEXT(..Saved, tPtr, tId) {
		Do ##class(EnsLib.HL7.Message).%DeleteId(tId)
	}
	Set ..Saved = ""
	Quit $$$OK
}

}
