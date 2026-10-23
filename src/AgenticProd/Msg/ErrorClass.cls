/// Format-neutral error classes. Format skills (HL7, FHIR, ...) map their own errors onto these.
Class AgenticProd.Msg.ErrorClass Extends %String [ ClassType = datatype ]
{

Parameter MAXLEN = 20;

Parameter VALUELIST = ",UNMAPPED_CODE,MISSING_FIELD,BAD_FORMAT,INVALID_VALUE,IDENTITY_ISSUE,STRUCTURE_ERROR,ROUTING,TRANSIENT,OTHER";

}
