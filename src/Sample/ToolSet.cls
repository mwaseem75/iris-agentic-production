Class Sample.ToolSet Extends %AI.ToolSet [DependsOn=Sample.Tools]
{
    XData Definition
    {
        <ToolSet>
            <Description>Sample Toolset</Description>
            
            <!-- Example audit policy (prints tool calls to console) --> 
            <!-- Does not work in MCP servers (as requires access to console) --> 
            <!-- <Policies> 
                <Audit Class="%AI.Policy.ConsoleAudit"/>
            </Policies> -->
            <Include Class="Sample.Tools"></Include>
            <MCP Name="PythonServer">
                <Stdio Executable="/usr/irissys/bin/irispython" 
                Args="/home/irisowner/dev/src/Python/multiplication_mcp.py" />
            </MCP>
        </ToolSet>
    }    
}

