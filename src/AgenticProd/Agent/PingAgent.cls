/// No tools, no skills: one short Chat for the Settings page's "Test connection".
Class AgenticProd.Agent.PingAgent Extends AgenticProd.Agent.Base
{

Parameter PROVIDER = "openai";

Parameter MODEL = "gpt-4o-mini";

Parameter APIKEY = "@{env:OPENAI_API_KEY}";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You check that the connection works. Answer with the single word OK.
}

}
