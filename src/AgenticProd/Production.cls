/// Agentic Production: lab results in from files, routed to simulated NPHIES; failures go to
/// Triage, which asks the agent and then applies, resends, rejects or escalates.
Class AgenticProd.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="AgenticProd.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Agentic Production: Self-Healing Interoperability</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="LabFileIn" Category="Lab" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="ORU^R01 files from LAB_SIM">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Host" Name="TargetConfigNames">LabRouter</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
  </Item>
  <Item Name="LabRouter" Category="Lab" ClassName="AgenticProd.Process.LabRouter" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Validate, LabCodeMap lookup, transform; failures to Triage">
    <Setting Target="Host" Name="TargetConfigName">NphiesOut</Setting>
    <Setting Target="Host" Name="TriageTarget">Triage</Setting>
    <Setting Target="Host" Name="FHIROutput">1</Setting>
    <Setting Target="Host" Name="FHIRTarget">NphiesFHIROut</Setting>
  </Item>
  <Item Name="NphiesOut" Category="Lab" ClassName="AgenticProd.Operation.NphiesOut" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Simulated NPHIES: files in data/out">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/out/</Setting>
    <Setting Target="Host" Name="SimulateTimeoutFor">MSG00015,15</Setting>
  </Item>
  <Item Name="NphiesFHIROut" Category="Lab" ClassName="AgenticProd.Operation.NphiesFHIROut" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Simulated NPHIES FHIR endpoint: validated R4 bundles in data/out-fhir">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/out-fhir/</Setting>
    <Setting Target="Adapter" Name="Charset">UTF-8</Setting>
  </Item>
  <Item Name="Triage" Category="Agent" ClassName="AgenticProd.Process.Triage" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Action matrix: the only component that acts on a decision">
    <Setting Target="Host" Name="AgentTarget">TriageAgent</Setting>
    <Setting Target="Host" Name="TargetConfigName">LabRouter</Setting>
    <Setting Target="Host" Name="ApprovalTarget">IntegrationSupport</Setting>
    <Setting Target="Host" Name="AutoFixThreshold">0.85</Setting>
  </Item>
  <Item Name="TriageAgent" Category="Agent" ClassName="AgenticProd.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="AI Hub triage agent (read-only)">
    <Setting Target="Host" Name="Model">gpt-4o-mini</Setting>
    <Setting Target="Host" Name="MaxIterations">8</Setting>
    <Setting Target="Host" Name="MaxToolCalls">10</Setting>
    <Setting Target="Host" Name="MaxTokensPerMessage">50000</Setting>
    <Setting Target="Host" Name="DailyTokenBudget">200000</Setting>
    <Setting Target="Host" Name="RunAsUser">agentic_agent</Setting>
    <Setting Target="Host" Name="Mode">live</Setting>
  </Item>
  <Item Name="IntegrationSupport" Category="Agent" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Workflow role: reviewers approve or reject MAP_CODE and ESCALATE tasks">
  </Item>
  <Item Name="TestTrigger" Category="Test" ClassName="AgenticProd.Service.TestTrigger" PoolSize="0" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Sends one synthetic TriageRequest">
    <Setting Target="Host" Name="TargetConfigName">TriageAgent</Setting>
    <Setting Target="Host" Name="ResponseTimeout">120</Setting>
  </Item>
</Production>
}

}
