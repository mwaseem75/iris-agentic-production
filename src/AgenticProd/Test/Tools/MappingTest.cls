/// Tools.Mapping on the search_loinc knowledge base (FastEmbed, local) and LabCodeMap. No LLM.
/// Needs Setup.BuildLoincKB() and Setup.SeedLabCodeMap().
Class AgenticProd.Test.Tools.MappingTest Extends AgenticProd.Test.Case
{

/// Local code used only by these tests' DecisionLog rows.
Parameter TESTCODE = "ZZMAP-01";

Method TestSearchLoincGlucose()
{
	Set tOut = {}.%FromJSON(##class(AgenticProd.Tools.Mapping).%New().SearchLoinc("Glucose", "serum", "mg/dL"))
	Set tHits = tOut.candidates
	Do $$$AssertEquals(tHits.%Size(), 5)
	Do $$$AssertNotTrue(tOut.%IsDefined("warning"), "specimen given")
	Do $$$AssertEquals(tHits.%Get(0).loinc, "2345-7", "top hit: "_tHits.%Get(0).%ToJSON())
	Do $$$AssertEquals(tHits.%Get(0).system, "Ser/Plas")
}

/// No method in the query: the general HbA1c code comes back marked method none, the
/// HPLC/electrophoresis codes with their method (case 02).
Method TestSearchLoincMethod()
{
	Set tHits = {}.%FromJSON(##class(AgenticProd.Tools.Mapping).%New().SearchLoinc("Hemoglobin A1c", "blood", "%")).candidates
	Set tMethods = ""
	For i = 0:1:tHits.%Size() - 1 {
		Set tHit = tHits.%Get(i), tMethods(tHit.loinc) = tHit.method
	}
	Do $$$AssertEquals($GET(tMethods("4548-4")), "none", "4548-4 returned, method none: "_tHits.%ToJSON())
	Do $$$AssertEquals($GET(tMethods("17856-6")), "HPLC")
	Do $$$AssertEquals($GET(tMethods("4549-2")), "Electrophoresis")
}

/// Troponin I and T high-sensitivity both fit serum + ng/L: the skill must ESCALATE on this.
Method TestSearchLoincTroponinReturnsBoth()
{
	Set tOut = ##class(AgenticProd.Tools.Mapping).%New().SearchLoinc("Troponin", "serum", "ng/L")
	Do $$$AssertTrue(tOut [ """89579-7""", "troponin I hs: "_tOut)
	Do $$$AssertTrue(tOut [ """67151-1""", "troponin T hs")
}

/// Case 39: glucose with no specimen fits blood, urine and serum, so the result carries a warning.
Method TestSearchLoincNoSpecimenWarns()
{
	Set tOut = {}.%FromJSON(##class(AgenticProd.Tools.Mapping).%New().SearchLoinc("Glucose", "", "mg/dL"))
	Do $$$AssertEquals(tOut.warning, "no specimen given; candidates differ by specimen", tOut.%ToJSON())
}

/// The rule on fixed candidates: only a same-test rival in another system, in the top 3, warns.
Method TestSpecimenWarning()
{
	Set tBld = {"loinc":"2339-0", "display":"Glucose [Mass/volume] in Blood", "system":"Bld", "method":"none", "units":"mg/dL"}
	Set tSer = {"loinc":"2345-7", "display":"Glucose [Mass/volume] in Serum or Plasma", "system":"Ser/Plas", "method":"none", "units":"mg/dL"}
	Set tFasting = {"loinc":"1558-6", "display":"Fasting glucose [Mass/volume] in Serum or Plasma", "system":"Ser/Plas", "method":"none", "units":"mg/dL"}
	Set tMolar = {"loinc":"15074-8", "display":"Glucose [Moles/volume] in Blood", "system":"Bld", "method":"none", "units":"mmol/L"}
	Set tWarn = "no specimen given; candidates differ by specimen"
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("", [(tSer), (tBld)]), tWarn)
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("serum", [(tSer), (tBld)]), "", "specimen given")
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("", [(tSer), (tFasting)]), "", "same system, other test")
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("", [(tSer), (tMolar)]), "", "other property and units")
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("", [(tSer), (tFasting), (tFasting), (tBld)]), "", "rival outside the top 3")
	Do $$$AssertEquals(##class(AgenticProd.Tools.Mapping).SpecimenWarning("", [(tSer)]), "")
}

Method TestLookupCode()
{
	Set tTools = ##class(AgenticProd.Tools.Mapping).%New()
	Set tHit = {}.%FromJSON(tTools.LookupCode("NA-S", "LAB_SIM"))
	Do $$$AssertEquals(tHit.loinc, "2951-2")
	Do $$$AssertEquals(tTools.LookupCode("GLU-01", "LAB_SIM"), "none", "unmapped on purpose")
}

/// Only approved mappings count as history.
Method TestSimilarPastMappingsApprovedOnly()
{
	For tOutcome = "APPROVED", "SENT_FOR_APPROVAL" {
		Set tRow = ##class(AgenticProd.Data.DecisionLog).%New()
		Set tRow.HeaderId = -9400, tRow.Decision = "MAP_CODE", tRow.ErrorClass = "UNMAPPED_CODE"
		Set tRow.LocalCode = ..#TESTCODE, tRow.Loinc = "2345-7", tRow.Outcome = tOutcome
		Set tRow.Reason = "Glucose serum mg/dL "_tOutcome
		Do $$$AssertStatusOK(tRow.%Save())
	}
	Set tTools = ##class(AgenticProd.Tools.Mapping).%New()
	Set tList = ..Data(tTools.SimilarPastMappings(..#TESTCODE, ""))
	Do $$$AssertEquals(tList.%Size(), 1, "approved row only")
	Do $$$AssertEquals(tList.%Get(0).loinc, "2345-7")
	Do $$$AssertTrue(..Data(tTools.SimilarPastMappings("", "glucose serum mg/dL approved")).%Size() >= 1, "matched by text")
	Do $$$AssertTrue(tTools.SimilarPastMappings("", "") [ "ERROR")
}

/// Running the build again replaces rows by source instead of adding copies.
Method TestRebuildIsIdempotent()
{
	Set tBefore = ..KBRows()
	Do $$$AssertStatusOK(##class(AgenticProd.Setup).BuildLoincKB(.tCount))
	Do $$$AssertEquals(..KBRows(), tBefore)
	Do $$$AssertEquals(tCount, tBefore, "one row per CSV line")
}

/// JSON inside the untrusted_data block.
Method Data(pOut As %String) As %DynamicArray
{
	Quit [].%FromJSON($PIECE(pOut, $CHAR(10), 2))
}

Method KBRows() As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM "_##class(AgenticProd.Tools.Mapping).#LOINCTABLE)
	Do tRS.%Next()
	Quit tRS.N
}

Method OnAfterAllTests() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.DecisionLog WHERE LocalCode = ?", ..#TESTCODE)
	Quit $$$OK
}

}
