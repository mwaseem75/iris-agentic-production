Class Sample.Agent Extends %AI.Agent
{
    /// LLM Model
    Parameter MODEL = "gpt-5-nano";

    /// Toolsets that the agent can use
    Parameter TOOLSETS = "Sample.ToolSet";
    
    /// System Prompt
    XData INSTRUCTIONS [ MimeType = text/markdown ]
    {
    # Sample Assistant

    You are a helpful assistant with access to a set of tools to interact with a database of people.
    }

    Method %OnInit() As %Status
    {
        // Set provider with API key from environment variable
        Set key = $System.Util.GetEnviron("OPENAI_API_KEY")  // or whatever
        Set ..Provider = ##class(%AI.Provider).Create("openai", {"api_key": (key)})
        
        Return $$$OK
    }


}
