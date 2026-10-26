/// HL7 -> SDA3 -> FHIR R4 build and validation on eval cases, called directly (no production, no LLM).
/// The first profile check starts the Java validator, so the first test can take about 35 s.
Class AgenticProd.Test.Operation.NphiesFHIROutTest Extends %UnitTest.TestCase
{

Parameter PROFILE = "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab|3.1.0";

Property Validator As HS.FHIRServer.Util.ResourceValidator;

Method OnBeforeAllTests() As %Status
{
	$$$QuitOnError(##class(AgenticProd.Setup).SeedLabCodeMap())
	Set tSC = ##class(AgenticProd.Operation.NphiesFHIROut).NewValidator("hl7.fhir.r4.core@4.0.1,hl7.fhir.us.core@3.1.0", .tValidator)
	Set ..Validator = tValidator
	Quit tSC
}

Method TestValidControl20()
{
	Do ..Bundle("20", .tBundle, .tMsg)
	Do $$$AssertEquals(tMsg.GetValueAt("3:0"), "OBR", "source message keeps having no ORC")
	Set tObs = ..First(tBundle, "Observation")
	Do $$$AssertTrue($IsObject(..First(tBundle, "Patient")), "Patient")
	Do $$$AssertTrue($IsObject(..First(tBundle, "DiagnosticReport")), "DiagnosticReport")
	If '$$$AssertTrue($IsObject(tObs), "Observation") Quit
	Set tLoinc = tObs.code.coding.%Get(0), tLocal = tObs.code.coding.%Get(1)
	Do $$$AssertEquals(tLoinc.system_"|"_tLoinc.code, "http://loinc.org|2951-2")
	Do $$$AssertEquals(tLoinc.display, "Sodium [Moles/volume] in Serum or Plasma")
	Do $$$AssertEquals(tLocal.code, "NA-S", "local code kept as second coding")
	Set tQty = tObs.valueQuantity
	Do $$$AssertEquals(tQty.value_" "_tQty.code_" "_tQty.system, "139 mmol/L http://unitsofmeasure.org")
	Set tErrors = ##class(AgenticProd.Operation.NphiesFHIROut).Validate(..Validator, tBundle, ..#PROFILE, .tOutcome, .tLines)
	Do $$$AssertEquals(tErrors, 0, "valid: "_tLines)
}

/// A bundle whose value is broken after the build is invalid, and LabRouter turns that into a
/// TriageRequest with Format FHIR.
Method TestBrokenValueToTriage()
{
	Do ..Bundle("20", .tBundle, .tMsg, .tHeaderId)
	Set tObs = ..First(tBundle, "Observation")
	Set tObs.valueQuantity.value = "one-three-nine"
	Set tResult = ##class(AgenticProd.Msg.FHIRResult).%New()
	Set tResult.IssueCount = ##class(AgenticProd.Operation.NphiesFHIROut).Validate(..Validator, tBundle, ..#PROFILE, .tOutcome, .tLines)
	Set tResult.Valid = (tResult.IssueCount = 0), tResult.Issues = tLines
	Do $$$AssertTrue(tResult.IssueCount > 0, tLines)
	Do $$$AssertTrue(tLines [ "WrongJsonType", tLines)
	Do $$$AssertEquals(tOutcome.issue.%Get(0).expression.%Get(0), "Bundle.entry[5]")

	Do ##class(AgenticProd.Process.LabRouter).FHIRProblem(tResult, .tClass, .tText)
	Do $$$AssertEquals(tClass, "BAD_FORMAT")
	Set tRouter = ##class(AgenticProd.Process.LabRouter).%New("LabRouter")
	Set tRouter.%PrimaryRequestHeader = ##class(Ens.MessageHeader).%OpenId(tHeaderId)
	Set tRequest = tRouter.TriageRequest(tMsg, tClass, tText, "FHIR")
	Do $$$AssertEquals(tRequest.Format, "FHIR")
	Do $$$AssertEquals(tRequest.HeaderId, tHeaderId, "points at the original HL7 message")
	Do $$$AssertTrue($EXTRACT(tRequest.ErrorText, 1, 6) = "FHIR: ", tRequest.ErrorText)
	Do $$$AssertEquals(##class(AgenticProd.Process.Triage).CheckerFor("FHIR"), "", "no FHIR checker yet, so Triage escalates without the agent")
}

/// After the reviewer approved GLU-01 -> 2345-7 (case 01 flow), the Observation carries that LOINC.
Method TestApprovedMapping01()
{
	Set tHad = ##class(Ens.Util.FunctionSet).Lookup("LabCodeMap", "GLU-01")
	Do ##class(Ens.Util.LookupTable).%UpdateValue("LabCodeMap", "GLU-01", "2345-7^Glucose [Mass/volume] in Serum or Plasma")
	Do ..Bundle("01", .tBundle)
	Set tObs = ..First(tBundle, "Observation")
	If $$$AssertTrue($IsObject(tObs), "Observation") {
		Do $$$AssertEquals(tObs.code.coding.%Get(0).code, "2345-7")
		Do $$$AssertEquals(tObs.code.coding.%Get(1).code, "GLU-01")
		Set tErrors = ##class(AgenticProd.Operation.NphiesFHIROut).Validate(..Validator, tBundle, ..#PROFILE, , .tLines)
		Do $$$AssertEquals(tErrors, 0, "valid: "_tLines)
	}
	// GLU-01 must stay unmapped for the eval and the learning-loop test
	If tHad = "" Do ##class(Ens.Util.LookupTable).%RemoveValue("LabCodeMap", "GLU-01")
}

Method Bundle(pCaseId As %String, Output pBundle As %DynamicObject, Output pMsg As EnsLib.HL7.Message, Output pHeaderId As %Integer)
{
	Do $$$AssertStatusOK(##class(AgenticProd.Test.Tools.HL7Test).LoadCase(pCaseId, .pHeaderId))
	Do ##class(AgenticProd.Tools.Base).OpenBody(pHeaderId, .pMsg)
	Do $$$AssertStatusOK(##class(AgenticProd.Operation.NphiesFHIROut).Build(pMsg, .pBundle))
}

ClassMethod First(pBundle As %DynamicObject, pType As %String) As %DynamicObject
{
	Set tIter = pBundle.entry.%GetIterator()
	While tIter.%GetNext(, .tEntry) {
		Quit:tEntry.resource.resourceType=pType
	}
	Quit $SELECT($IsObject($GET(tEntry)) && (tEntry.resource.resourceType = pType): tEntry.resource, 1: "")
}

Method OnAfterAllTests() As %Status
{
	Quit ##class(AgenticProd.Test.Tools.HL7Test).Cleanup()
}

}
