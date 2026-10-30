/// Customer-side demo: a plain orders/results interface with no AI, in its own namespace (LEGACY).
/// Orders go to the lab, billing and the label printer; results go to the EHR. Some samples fail
/// on purpose (unmapped code, missing segment, no specimen, billing down) for the plug-in demo.
Class Legacy.OrdersProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Legacy.OrdersProduction" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Legacy orders and results interface (no AI)</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="OrdersFileIn" Category="Orders" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="ORM^O01 orders and ORU^R01 results dropped by the hospital systems">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/legacy/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/home/irisowner/dev/data/legacy/archive/</Setting>
    <Setting Target="Host" Name="TargetConfigNames">OrdersRouter</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
  </Item>
  <Item Name="OrdersRouter" Category="Orders" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="Orders to lab, billing, labels; results to the EHR">
    <Setting Target="Host" Name="BusinessRuleName">Legacy.OrdersRoutingRule</Setting>
    <Setting Target="Host" Name="Validation">dm</Setting>
    <Setting Target="Host" Name="ActOnTransformError">1</Setting>
    <Setting Target="Host" Name="ActOnValidationError">1</Setting>
  </Item>
  <Item Name="LabOrdersOut" Category="Orders" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="Orders to the lab system">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/legacy/lab/</Setting>
    <Setting Target="Host" Name="Filename">%f_%Q.hl7</Setting>
  </Item>
  <Item Name="BillingOut" Category="Orders" ClassName="EnsLib.HL7.Operation.HTTPOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="Billing system over HTTP; down in the demo, so every order fails here after FailureTimeout">
    <Setting Target="Adapter" Name="HTTPServer">localhost</Setting>
    <Setting Target="Adapter" Name="HTTPPort">9</Setting>
    <Setting Target="Adapter" Name="URL">/billing/hl7</Setting>
    <Setting Target="Host" Name="FailureTimeout">15</Setting>
  </Item>
  <Item Name="LabelPrinter" Category="Orders" ClassName="Legacy.Operation.LabelPrinter" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="Specimen labels (Embedded Python)">
    <Setting Target="Host" Name="LabelPath">/home/irisowner/dev/data/legacy/labels/</Setting>
  </Item>
  <Item Name="ResultsOut" Category="Results" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="false" Comment="Results to the EHR, LOINC coded">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/legacy/ehr/</Setting>
    <Setting Target="Host" Name="Filename">%f_%Q.hl7</Setting>
  </Item>
</Production>
}

}
