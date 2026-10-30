/// Orders fan out to lab, billing and labels; results go through the code mapping to the EHR.
Class Legacy.OrdersRoutingRule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="Legacy.OrdersProduction">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="Orders" disabled="false">
<constraint name="source" value="OrdersFileIn"></constraint>
<constraint name="msgClass" value="EnsLib.HL7.Message"></constraint>
<constraint name="docCategory" value="2.5.1"></constraint>
<constraint name="docName" value="ORM_O01"></constraint>
<when condition="1">
<send transform="" target="LabOrdersOut,BillingOut,LabelPrinter"></send>
<return></return>
</when>
</rule>
<rule name="Results" disabled="false">
<constraint name="source" value="OrdersFileIn"></constraint>
<constraint name="msgClass" value="EnsLib.HL7.Message"></constraint>
<constraint name="docCategory" value="2.5.1"></constraint>
<constraint name="docName" value="ORU_R01"></constraint>
<when condition="1">
<send transform="Legacy.DTL.ResultToEHR" target="ResultsOut"></send>
<return></return>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
