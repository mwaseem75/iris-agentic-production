/// Lab ORU^R01 to the EHR: OBX-3 local code -> LOINC from lookup LegacyLabCodes.
/// The EHR rejects local codes, so an unmapped code fails the message instead of passing it on.
Class Legacy.DTL.ResultToEHR Extends Ens.DataTransformDTL [ DependsOn = EnsLib.HL7.Message ]
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASNULL = 0;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5.1:ORU_R01' targetDocType='2.5.1:ORU_R01' create='copy' language='objectscript' >
<code>
<![CDATA[
	For tI = 1:1:target.SegCount {
		Set tSeg = target.GetSegmentAt(tI)
		Continue:'$IsObject(tSeg)
		Continue:tSeg.Name'="OBX"
		Set tLocal = target.GetValueAt(tI_":3.1")
		Set tLoinc = ##class(Ens.Util.FunctionSet).Lookup("LegacyLabCodes", tLocal)
		If tLoinc="" $$$ThrowStatus($$$ERROR($$$GeneralError, "Unmapped lab code '"_tLocal_"' in OBX "_target.GetValueAt(tI_":1")_": no entry in LegacyLabCodes"))
		$$$ThrowOnError(target.SetValueAt(tLoinc_"^"_target.GetValueAt(tI_":3.2")_"^LN", tI_":3"))
	}
]]></code>
</transform>
}

}
