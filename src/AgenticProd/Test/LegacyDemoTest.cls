/// Legacy demo (Setup.LegacyDemo): namespace, lookup, and the two components that fail on purpose.
/// Runs the label renderer and the DTL in LEGACY directly; nothing goes through the production.
Class AgenticProd.Test.LegacyDemoTest Extends %UnitTest.TestCase
{

Parameter SAMPLES = "/home/irisowner/dev/legacy/samples/";

Property Dir As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Dir = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_"Temp/legacytest"_$JOB)
	Do ##class(%File).RemoveDirectoryTree(..Dir)
	Quit ##class(%File).CreateDirectoryChain(..Dir)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..Dir)
	Quit $$$OK
}

Method TestNamespace()
{
	Set tNS = ##class(AgenticProd.Setup).#LEGACYNS
	Do $$$AssertTrue(##class(%SYS.Namespace).Exists(tNS), tNS_" exists")
	New $NAMESPACE
	Set $NAMESPACE = tNS
	Do $$$AssertTrue(##class(%EnsembleMgr).IsEnsembleNamespace(), "interop enabled")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("Legacy.OrdersProduction"), "production compiled")
	Do $$$AssertEquals(##class(Ens.Util.FunctionSet).Lookup("LegacyLabCodes", "GLU"), "2345-7")
	Do $$$AssertEquals(##class(Ens.Util.FunctionSet).Lookup("LegacyLabCodes", "HBA1C-L"), "", "left unmapped for sample 04")
}

Method TestLabel()
{
	New $NAMESPACE
	Set $NAMESPACE = ##class(AgenticProd.Setup).#LEGACYNS
	Set tFile = ##class(Legacy.Operation.LabelPrinter).RenderLabel(..Sample("01-order-ok.hl7").OutputToString(), ..Dir)
	Do $$$AssertEquals(tFile, ..Dir_"label_ORD2001.txt")
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tFile)
	Set tText = tStream.Read()
	Do $$$AssertTrue(tText [ "SPEC   SER", "specimen from OBR-15")
	Do $$$AssertTrue(tText [ "MRN    200001", "MRN from PID-3.1")
	Try {
		Do ##class(Legacy.Operation.LabelPrinter).RenderLabel(..Sample("02-order-no-specimen.hl7").OutputToString(), ..Dir)
		Do $$$AssertFailure("no specimen should raise")
	} Catch ex {
		Do $$$AssertTrue(ex.DisplayString() [ "no specimen in OBR-15 for order ORD2002", ex.DisplayString())
	}
}

Method TestResultTransform()
{
	New $NAMESPACE
	Set $NAMESPACE = ##class(AgenticProd.Setup).#LEGACYNS
	Do $$$AssertStatusOK(##class(Legacy.DTL.ResultToEHR).Transform(..Sample("03-result-ok.hl7"), .tOut))
	Do $$$AssertEquals(tOut.GetValueAt("4:3"), "2345-7^Glucose^LN")
	Set tSC = ##class(Legacy.DTL.ResultToEHR).Transform(..Sample("04-result-unmapped-code.hl7"), .tOut)
	Do $$$AssertStatusNotOK(tSC, "unmapped code fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(tSC) [ "Unmapped lab code 'HBA1C-L'", $SYSTEM.Status.GetErrorText(tSC))
}

/// Unsaved message from legacy/samples, as OrdersFileIn would parse it.
Method Sample(pName As %String) As EnsLib.HL7.Message
{
	Set tMsg = ##class(EnsLib.HL7.Message).ImportFromFile(..#SAMPLES_pName, , .tSC)
	Do $$$AssertStatusOK(tSC, "import "_pName)
	Set tMsg.DocType = "2.5.1:"_$TRANSLATE(tMsg.GetValueAt("1:9.3"), "^", "_")
	Quit tMsg
}

}
