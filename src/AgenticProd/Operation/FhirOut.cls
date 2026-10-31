Include (Ensemble, HS.FHIRServer)

/// Simulated FHIR server (HIE). HL7 v2 ORU^R01 (already checked by LabRouter) -> SDA3 -> FHIR R4
/// bundle with LOINC codings, validated structurally and against the lab profile. A valid bundle is
/// written to the adapter FilePath; an invalid one is only reported back in the FHIRResult.
Class AgenticProd.Operation.FhirOut Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.File.OutboundAdapter";

Property Adapter As EnsLib.File.OutboundAdapter;

/// Profile every Observation must meet, "url|version". US Core lab is the target profile.
Property ObservationProfile As %String(MAXLEN = 500) [ InitialExpression = "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab|3.1.0" ];

/// FHIR packages loaded for validation, comma-separated; must include the profile's package.
Property Packages As %String(MAXLEN = 500) [ InitialExpression = "hl7.fhir.r4.core@4.0.1,hl7.fhir.us.core@3.1.0" ];

/// Code system URI for LAB_SIM's own test codes (OBX-3 coding system L), kept as the second coding.
Property LocalCodeSystem As %String(MAXLEN = 500) [ InitialExpression = "http://lab-sim.example/codes" ];

Property Validator As HS.FHIRServer.Util.ResourceValidator [ Transient ];

/// OBX-8 flags that are also codes in v3-ObservationInterpretation, with their display.
Parameter INTERPRETATIONS = "N:Normal,H:High,L:Low,A:Abnormal,HH:Critical high,LL:Critical low,AA:Critical abnormal";

Parameter SETTINGS = "ObservationProfile:FHIR,Packages:FHIR,LocalCodeSystem:FHIR";

Method OnInit() As %Status
{
	Set tSC = ..NewValidator(..Packages, .tValidator)
	If $$$ISERR(tSC) Quit tSC
	Set ..Validator = tValidator
	// The first profile check starts the Java validator (about 35 s); pay that here, not on a message
	Set tStart = $ZHOROLOG
	Set tSC = ..Warm(tValidator, ..ObservationProfile)
	If $$$ISERR(tSC) {
		// On an item restart the old job's OnTearDown has just stopped the JVM and the gateway
		// still points at its port; start it again and retry once
		Do $SYSTEM.external.startServer($$$ValidatorELS)
		Set tSC = ..Warm(tValidator, ..ObservationProfile)
	}
	If $$$ISERR(tSC) {
		$$$LOGWARNING("FHIR validator not warmed: "_$SYSTEM.Status.GetErrorText(tSC))
	} Else {
		$$$LOGINFO("FHIR validator warm in "_$JUSTIFY($ZHOROLOG - tStart, 0, 1)_" s")
	}
	Quit $$$OK
}

Method OnTearDown() As %Status
{
	// The validator JVM is shared by the instance but only this host uses it; do not leave it idle
	Do $SYSTEM.external.stopServer($$$ValidatorELS)
	Quit $$$OK
}

Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As AgenticProd.Msg.FHIRResult) As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..Build(pRequest, .tBundle, ..LocalCodeSystem))
		Set pResponse = ##class(AgenticProd.Msg.FHIRResult).%New()
		Set pResponse.ControlId = pRequest.GetValueAt("1:10")
		Set tErrors = ..Validate(..Validator, tBundle, ..ObservationProfile, .tOutcome, .tLines)
		Set pResponse.Valid = (tErrors = 0), pResponse.IssueCount = tErrors, pResponse.Issues = tLines
		If tErrors {
			Do pResponse.Outcome.Write(tOutcome.%ToJSON())
			$$$LOGWARNING("FHIR bundle for "_pRequest.GetValueAt("1:10")_" invalid, "_tErrors_" issue(s): "_tOutcome.%ToJSON())
			Quit
		}
		Set tStream = ##class(%Stream.TmpCharacter).%New()
		$$$ThrowOnError(##class(%JSON.Formatter).%New().FormatToStream(tBundle, tStream))
		Set pResponse.FileName = ..Adapter.CreateFilename(pRequest.GetValueAt("1:10"), "%f_%Q.json")
		$$$ThrowOnError(..Adapter.PutStream(pResponse.FileName, tStream))
		$$$TRACE("FHIR bundle written: "_pResponse.FileName)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// pBundle: FHIR R4 transaction bundle for pMsg, Observation codes carrying LOINC from LabCodeMap
/// and the local code under pLocalSystem. pMsg is not changed.
ClassMethod Build(pMsg As EnsLib.HL7.Message, Output pBundle As %DynamicObject, pLocalSystem As %String = "") As %Status
{
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..Enrich(pMsg, .tCopy))
		$$$ThrowOnError(##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(tCopy, .tSDA))
		Set pBundle = ##class(HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR).TransformStream(tSDA, "HS.SDA3.Container", "R4").bundle
		Do ..AddLoinc(pBundle, pLocalSystem)
		Do ..AddInterpretation(pBundle)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Copy of pMsg with an ORC before the first OBR when there is none, and ORC-29 = LAB.
ClassMethod Enrich(pMsg As EnsLib.HL7.Message, Output pCopy As EnsLib.HL7.Message) As %Status
{
	Set pCopy = pMsg.%ConstructClone()
	Set:pCopy.DocType="" pCopy.DocType = "2.5.1:ORU_R01"
	Set (tOrc, tObr) = 0
	For i = 1:1:pCopy.SegCount {
		Set tName = pCopy.GetSegmentAt(i).Name
		If tName = "ORC" Set tOrc = i  Quit
		If tName = "OBR" Set tObr = i  Quit
	}
	// HL7ToSDA3 picks lab/rad/other order from ORC-29; LAB_SIM sends no ORC, and without one the
	// SDA has no LabOrder, so the bundle has no Observation or DiagnosticReport at all
	If tOrc {
		Quit:pCopy.GetValueAt(tOrc_":29")'="" $$$OK
		Quit pCopy.SetValueAt("LAB", tOrc_":29")
	}
	Quit:'tObr $$$ERROR($$$GeneralError, "no OBR segment")
	Set tSeg = ##class(EnsLib.HL7.Segment).%New()
	Set tSeg.Separators = pCopy.Separators
	Do tSeg.SetValueAt("ORC", 0), tSeg.SetValueAt("RE", 1), tSeg.SetValueAt("LAB", 29)
	Quit pCopy.InsertSegmentAt(tSeg, tObr)
}

/// Put the LabCodeMap LOINC first in each Observation.code.coding and keep the local code after
/// it, with system pLocalSystem when it has none.
ClassMethod AddLoinc(pBundle As %DynamicObject, pLocalSystem As %String = "")
{
	Set tIter = pBundle.entry.%GetIterator()
	While tIter.%GetNext(, .tEntry) {
		Set tRes = tEntry.resource
		Continue:tRes.resourceType'="Observation"
		Set tLocal = tRes.code.coding.%Get(0)
		Continue:'$IsObject(tLocal)
		Set:(pLocalSystem'="")&&(tLocal.system="") tLocal.system = pLocalSystem
		Set tMap = ##class(Ens.Util.FunctionSet).Lookup("LabCodeMap", tLocal.code)
		Continue:tMap=""
		Set tCoding = [{"system":"http://loinc.org", "code":($PIECE(tMap, "^")), "display":($PIECE(tMap, "^", 2))}]
		Set tOld = tRes.code.coding.%GetIterator()
		While tOld.%GetNext(, .tC) {
			Do tCoding.%Push(tC)
		}
		Set tRes.code.coding = tCoding
	}
}

/// Observation.interpretation from OBX-8: SDA3ToFHIR gives only the flag as display and text, so
/// a known flag gets a v3-ObservationInterpretation coding. Unknown flags stay as text.
ClassMethod AddInterpretation(pBundle As %DynamicObject)
{
	Set tIter = pBundle.entry.%GetIterator()
	While tIter.%GetNext(, .tEntry) {
		Set tRes = tEntry.resource
		Continue:(tRes.resourceType'="Observation")||'$IsObject(tRes.interpretation)
		Set tConcepts = tRes.interpretation.%GetIterator()
		While tConcepts.%GetNext(, .tConcept) {
			Set tFlag = $ZSTRIP(tConcept.text, "<>W")
			Set:tFlag="" tFlag = $ZSTRIP(tConcept.coding.%Get(0).display, "<>W")
			Set tPos = $FIND(","_..#INTERPRETATIONS, ","_tFlag_":")
			Continue:(tFlag="")||'tPos
			Set tDisplay = $PIECE($EXTRACT(","_..#INTERPRETATIONS, tPos, *), ",")
			Set tConcept.coding = [{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation", "code":(tFlag), "display":(tDisplay)}]
		}
	}
}

/// Number of error/fatal issues in pBundle: base R4 structure for every resource, plus pProfile for
/// each Observation that passed it. pOutcome is an OperationOutcome with those issues; pLines has
/// one "Type[entry] expression: text" line per issue, "; "-separated.
ClassMethod Validate(pValidator As HS.FHIRServer.Util.ResourceValidator, pBundle As %DynamicObject, pProfile As %String, Output pOutcome As %DynamicObject, Output pLines As %String) As %Integer
{
	Set pOutcome = {"resourceType":"OperationOutcome", "issue":[]}, pLines = ""
	Set tIter = pBundle.entry.%GetIterator()
	While tIter.%GetNext(.tKey, .tEntry) {
		Set tRes = tEntry.resource, tWhere = "Bundle.entry["_tKey_"]"
		Set tStructural = 1
		Try {
			Do pValidator.ValidateResource(tRes)
		} Catch ex {
			Set tStructural = 0
			Do $SYSTEM.Status.DecomposeStatus(ex.AsStatus(), .tErr)
			For i = 1:1:$GET(tErr) {
				// The first error is only the "Details follow" wrapper
				Continue:tErr(i)["ValidationFailure"
				// "ERROR <HSFHIRErr>WrongJsonType: ..." -> "WrongJsonType: ..."
				Do ..AddIssue(pOutcome, .pLines, tRes.resourceType, tWhere, "", $SELECT(tErr(i) [ ">": $PIECE(tErr(i), ">", 2, *), 1: tErr(i)))
			}
			Kill tErr
		}
		Continue:'tStructural||(tRes.resourceType'="Observation")
		Try {
			Set tOO = pValidator.ValidateAgainstProfile(tRes, $LISTBUILD(pProfile))
			Set tIssues = tOO.issue.%GetIterator()
			While tIssues.%GetNext(, .tIssue) {
				Continue:(tIssue.severity'="error")&&(tIssue.severity'="fatal")
				Do ..AddIssue(pOutcome, .pLines, tRes.resourceType, tWhere, tIssue.expression.%Get(0), tIssue.details.text, tIssue.code)
			}
		} Catch ex {
			Do ..AddIssue(pOutcome, .pLines, tRes.resourceType, tWhere, "", "profile check failed: "_$SYSTEM.Status.GetErrorText(ex.AsStatus()))
		}
	}
	Quit pOutcome.issue.%Size()
}

ClassMethod AddIssue(pOutcome As %DynamicObject, ByRef pLines As %String, pType As %String, pWhere As %String, pExpr As %String, pText As %String, pCode As %String = "invalid") [ Internal ]
{
	Set tIssue = {"severity":"error", "code":(pCode), "diagnostics":(pText)}
	Set tIssue.expression = [(pWhere_$SELECT(pExpr '= "": "."_pExpr, 1: ""))]
	Do pOutcome.issue.%Push(tIssue)
	Set pLines = pLines_$SELECT(pLines '= "": "; ", 1: "")_pType_" "_tIssue.expression.%Get(0)_": "_pText
}

ClassMethod NewValidator(pPackages As %String, Output pValidator As HS.FHIRServer.Util.ResourceValidator) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tList = ""
		For i = 1:1:$LENGTH(pPackages, ",") {
			Set tList = tList_$LISTBUILD($ZSTRIP($PIECE(pPackages, ",", i), "<>W"))
		}
		Set pValidator = ##class(HS.FHIRServer.Util.ResourceValidator).%New(##class(HS.FHIRMeta.API).getInstance(tList))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// One profile check on a minimal lab Observation, to start the Java validator.
ClassMethod Warm(pValidator As HS.FHIRServer.Util.ResourceValidator, pProfile As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tObs = {"resourceType":"Observation", "status":"final",
			"category":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/observation-category", "code":"laboratory"}]}],
			"code":{"coding":[{"system":"http://loinc.org", "code":"2951-2"}]}, "subject":{"reference":"Patient/warm"},
			"effectiveDateTime":"2026-01-01T00:00:00Z", "valueQuantity":{"value":1, "system":"http://unitsofmeasure.org", "code":"mmol/L"}}
		Do pValidator.ValidateAgainstProfile(tObs, $LISTBUILD(pProfile))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
