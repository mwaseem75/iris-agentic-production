/// Drops eval cases into LabFileIn's folder so the production picks them up like any lab file.
/// Every case that fails the LabCodeMap lookup or validation goes to Triage, i.e. a live agent call.
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
