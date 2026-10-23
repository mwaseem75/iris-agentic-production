/// Agentic Production. Phase 1: the agent operation plus a test sender.
Class AgenticProd.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="AgenticProd.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Agentic Production: Self-Healing Interoperability</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="TestTrigger" Category="Test" ClassName="AgenticProd.Service.TestTrigger" PoolSize="0" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="Sends one synthetic TriageRequest">
    <Setting Target="Host" Name="TargetConfigName">TriageAgent</Setting>
    <Setting Target="Host" Name="ResponseTimeout">120</Setting>
  </Item>
  <Item Name="TriageAgent" Category="Agent" ClassName="AgenticProd.Operation.Agent" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Comment="AI Hub triage agent (read-only)">
    <Setting Target="Host" Name="Model">gpt-5-nano</Setting>
    <Setting Target="Host" Name="MaxIterations">3</Setting>
    <Setting Target="Host" Name="DailyTokenBudget">200000</Setting>
    <Setting Target="Host" Name="RunAsUser">agentic_agent</Setting>
  </Item>
</Production>
}

}
