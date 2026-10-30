Include Ensemble

/// Read-only code mapping tools for the triage agent: current LabCodeMap entry, LOINC candidates
/// from the search_loinc knowledge base, and mappings people approved before. Queries go through
/// %SQL.Statement only, so the agent role's SELECT grants apply.
Class AgenticProd.Tools.Mapping Extends %AI.ToolSet
{

/// Vector table of the search_loinc knowledge base (Setup.BuildLoincKB).
Parameter LOINCTABLE = "AgenticProd_KB.Loinc";

/// Lookup table the router maps OBX-3.1 with; values are "LOINC^display".
Parameter CODEMAP = "LabCodeMap";

Parameter TOPK = 5;

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="TriageMapping">
  <Description>Tools to map a local lab test code to LOINC: check the current mapping, search LOINC candidates, and see mappings people approved before.</Description>
  <Tool Name="lookup_code" Method="LookupCode">
    <Description>Check whether a local test code (OBX-3.1) already has a LOINC mapping in this production's code table. localCode is the code exactly as sent, e.g. "GLU-01"; source is the sending application from MSH-3, e.g. "LAB_SIM". Returns the mapping as JSON, or "none" when the code is unmapped.</Description>
  </Tool>
  <Tool Name="search_loinc" Method="SearchLoinc">
    <Description>Search the LOINC subset for candidate codes. text is the test name from OBX-3.2 (e.g. "Glucose", "Troponin"); specimen is the specimen if known (e.g. "serum", "blood", "urine"); units is OBX-6 (e.g. "mg/dL"). Returns JSON {"candidates":[...]} with up to 5 candidates, each with loinc, display, system (specimen), method, units and score (higher is closer). If the result has a "warning", do not pick a candidate: ESCALATE and quote the warning in evidence. method "none" is the general code for the test, with no specific lab method; any other method (e.g. "HPLC") is a method-specific code. The score only ranks text similarity: check that system, method and units agree with the message before you choose.</Description>
  </Tool>
  <Tool Name="similar_past_mappings" Method="SimilarPastMappings">
    <Description>Get mappings a person approved before for the same local code, or for a test name like text (e.g. "Glucose"). localCode and text may be empty, but not both. Returns up to 5 approved mappings as JSON with local_code, loinc, reason and created_at, newest first, or an empty list.</Description>
  </Tool>
</ToolSet>
}

/// Code table entry through SQL: the agent item's CodeTable (Operation.Agent sets
/// ^||AgenticProd.CodeTable for the run), else CODEMAP. Not per source yet; source is echoed so
/// the model sees which sender it checked. A value is "LOINC^display" or the bare LOINC.
Method LookupCode(localCode As %String, source As %String) As %String
{
	Set tTable = $GET(^||AgenticProd.CodeTable, ..#CODEMAP)
	$$$TRACE("lookup_code localCode="_localCode_" source="_source_" table="_tTable)
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DataValue FROM Ens_Util.LookupTable WHERE TableName = ? AND KeyName = ?", tTable, localCode)
	If tRS.%SQLCODE < 0 Quit "ERROR: SQLCODE "_tRS.%SQLCODE_" "_tRS.%Message
	Quit:'tRS.%Next() "none"
	Quit {"local_code":(localCode), "source":(source), "loinc":($PIECE(tRS.DataValue, "^")), "display":($PIECE(tRS.DataValue, "^", 2))}.%ToJSON()
}

/// Top candidates from the search_loinc knowledge base, as {"candidates":[...]} plus "warning"
/// from SpecimenWarning. Specimen and units go into the query text, not filters: "serum" never
/// equals the LOINC system "Ser/Plas".
Method SearchLoinc(text As %String, specimen As %String, units As %String) As %String
{
	$$$TRACE("search_loinc text="_text_" specimen="_specimen_" units="_units)
	Try {
		Set tQuery = $ZSTRIP(text_" "_specimen_" "_units, "<>=W")
		If tQuery = "" Return "ERROR: text is required"
		Set tHits = ..LoincSearch(tQuery)
		Set tOut = [], tIter = tHits.%GetIterator()
		While tIter.%GetNext(, .tHit) {
			Do tOut.%Push({"loinc":(tHit.metadata.loinc), "display":($PIECE(tHit.text, " | ")), "system":(tHit.metadata.system), "method":($SELECT(tHit.metadata.method'="": tHit.metadata.method, 1: "none")), "units":(tHit.metadata.units), "score":($NUMBER(tHit.score, 3))})
		}
		Set tResult = {"candidates":(tOut)}
		Set tWarning = ..SpecimenWarning(specimen, tOut)
		Set:tWarning'="" tResult.warning = tWarning
		Set tResult = tResult.%ToJSON()
	} Catch ex {
		Set tResult = ##class(AgenticProd.Tools.Base).ErrorText(ex.AsStatus())
	}
	Quit tResult
}

/// "no specimen given; candidates differ by specimen" when pSpecimen is empty and another of the
/// top 3 pCandidates is the top one's test in a different system (same analyte, method, units),
/// else "". Case 39: glucose with no specimen is 2339-0 Bld, 2350-7 Urine or 2345-7 Ser/Plas.
ClassMethod SpecimenWarning(pSpecimen As %String, pCandidates As %DynamicArray) As %String
{
	Quit:($ZSTRIP(pSpecimen, "<>W") '= "")||(pCandidates.%Size() < 2) ""
	Set tTop = pCandidates.%Get(0)
	// LOINC display names end with " in <system>"; the part before it is analyte and property
	Set tAnalyte = $PIECE(tTop.display, " in ")
	Set tLast = $SELECT(pCandidates.%Size() < 3: pCandidates.%Size(), 1: 3) - 1
	For i = 1:1:tLast {
		Set tHit = pCandidates.%Get(i)
		If (tHit.system '= tTop.system) && ($PIECE(tHit.display, " in ") = tAnalyte) && (tHit.method = tTop.method) && (tHit.units = tTop.units) {
			Return "no specimen given; candidates differ by specimen"
		}
	}
	Quit ""
}

/// Approved MAP_CODE decisions from DecisionLog (Outcome APPROVED, set by the Workflow step).
Method SimilarPastMappings(localCode As %String, text As %String) As %String
{
	$$$TRACE("similar_past_mappings localCode="_localCode_" text="_text)
	If (localCode = "") && (text = "") Quit "ERROR: give localCode or text"
	// IRIS binds "" as NULL, so only add the filters that have a value
	Set tSQL = "SELECT TOP 5 LocalCode, Loinc, Reason, CreatedAt FROM AgenticProd_Data.DecisionLog WHERE Decision = 'MAP_CODE' AND Outcome = 'APPROVED' AND ("
	Set tArgs = 0
	If localCode '= "" Set tSQL = tSQL_"LocalCode = ?", tArgs = tArgs + 1, tArgs(tArgs) = localCode
	If text '= "" Set tSQL = tSQL_$SELECT(tArgs: " OR ", 1: "")_"%UPPER(ErrorText) [ %UPPER(?) OR %UPPER(Reason) [ %UPPER(?)", tArgs = tArgs + 2, tArgs(tArgs - 1) = text, tArgs(tArgs) = text
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL_") ORDER BY ID DESC", tArgs...)
	If tRS.%SQLCODE < 0 Quit "ERROR: SQLCODE "_tRS.%SQLCODE_" "_tRS.%Message
	Set tList = []
	While tRS.%Next() {
		Do tList.%Push({"local_code":(tRS.LocalCode), "loinc":(tRS.Loinc), "reason":(tRS.Reason), "created_at":(tRS.CreatedAt)})
	}
	// Reasons were written from message text, so they stay marked as data
	Quit ##class(AgenticProd.Tools.Base).Untrusted("approved_mappings", "", tList.%ToJSON())
}

/// Hits from the knowledge base's own retrieval tool. AI Hub has no ObjectScript search API on
/// build 154 (KnowledgeBase only registers a tool, EmbedBatch refuses direct calls), so the KB is
/// attached to a private ToolMgr and its tool is executed there.
ClassMethod LoincSearch(pQuery As %String) As %DynamicArray [ Internal ]
{
	$$$ThrowOnError(..Prepare())
	Set tResult = %AgenticProdLoinc("mgr").ExecuteTool("search_loinc", {"query":(pQuery)})
	Quit $SELECT($IsObject(tResult.value): tResult.value, 1: [])
}

/// Build the search_loinc retrieval once per process and keep it in %AgenticProdLoinc.
/// VectorStore.Build always runs CREATE TABLE, which the agent role may not do, so
/// Operation.Agent calls this in OnInit, before the job switches to the agent user.
ClassMethod Prepare() As %Status
{
	Quit:$IsObject($GET(%AgenticProdLoinc("mgr"))) $$$OK
	Set tSC = $$$OK
	Try {
		Set tEmb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
		Set tVS = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set tVS.TableName = ..#LOINCTABLE, tVS.Dimensions = tEmb.Dimensions, tVS.ModelName = tEmb.ModelName
		$$$ThrowOnError(tVS.Build(..LoincFields()))
		Set tKB = ##class(%AI.RAG.KnowledgeBase).%New("search_loinc", "LOINC subset")
		Set tKB.TopK = ..#TOPK
		$$$ThrowOnError(tKB.Build(tEmb, tVS))
		Set tMgr = ##class(%AI.ToolMgr).%New()
		$$$ThrowOnError(tKB.AddToManager(tMgr))
		// All four stay referenced: closing one frees its native handle (Embedding.%OnClose)
		Set %AgenticProdLoinc("emb") = tEmb, %AgenticProdLoinc("vs") = tVS, %AgenticProdLoinc("kb") = tKB, %AgenticProdLoinc("mgr") = tMgr
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Promoted metadata columns of LOINCTABLE; Build must get the same list every time.
ClassMethod LoincFields() As %DynamicArray [ Internal ]
{
	Quit [{"name":"loinc", "type":"varchar(20)"}, {"name":"system", "type":"varchar(30)"}, {"name":"method", "type":"varchar(40)"}, {"name":"units", "type":"varchar(30)"}]
}

}
