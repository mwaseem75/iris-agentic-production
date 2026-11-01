/// Throwaway production for AddAgentTest. Never the current production, so adding and removing
/// items saves it without updating a running one.
Class AgenticProd.Test.Plugin.ScratchProd Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="AgenticProd.Test.Plugin.ScratchProd" TestingEnabled="false" LogGeneralTraceEvents="false">
  <Description>Scratch production for unit tests</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="ScratchOut" Category="Scratch" ClassName="EnsLib.File.PassthroughOperation" PoolSize="1" Enabled="false" Foreground="false" LogTraceEvents="false" Comment="Existing item, must stay as it is">
    <Setting Target="Adapter" Name="FilePath">/tmp/</Setting>
  </Item>
</Production>
}

}
