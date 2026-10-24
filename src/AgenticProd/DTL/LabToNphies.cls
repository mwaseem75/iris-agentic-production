/// LAB_SIM ORU^R01 to NPHIES_SIM: copy, then OBX-3 local code -> LOINC^display^LN from LabCodeMap.
/// LabRouter only calls it once every OBX-3.1 is mapped; an unmapped code is left as it is.
Class AgenticProd.DTL.LabToNphies Extends Ens.DataTransformDTL [ DependsOn = EnsLib.HL7.Message ]
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5.1:ORU_R01' targetDocType='2.5.1:ORU_R01' create='copy' language='objectscript' >
<code>
<![CDATA[
	// By segment index: OBX sits in nested groups, and index paths do not depend on DocType
	For tI = 1:1:target.SegCount {
		Set tSeg = target.GetSegmentAt(tI)
		Continue:'$IsObject(tSeg)
		Continue:tSeg.Name'="OBX"
		Set tMap = ##class(Ens.Util.FunctionSet).Lookup("LabCodeMap", target.GetValueAt(tI_":3.1"))
		Continue:tMap=""
		Set tSC = target.SetValueAt(tMap_"^LN", tI_":3")
		Quit:$$$ISERR(tSC)
	}
]]></code>
</transform>
}

}
