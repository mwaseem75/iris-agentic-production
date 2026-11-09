/// Fixture: an agent like the wizard makes, with tool sets and no skills. Never run; the map
/// test only reads its class parameters.
Class AgenticProd.Test.Plugin.NoSkillAgent Extends AgenticProd.Agent.Base
{

Parameter PROVIDER = "openai";

Parameter APIKEY = "@{env:OPENAI_API_KEY}";

Parameter MODEL = "gpt-4o-mini";

Parameter TOOLSETS = "AgenticProd.Tools.Base";

Parameter SKILLS;

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
Explain why a message failed.

## Output
Reply with one JSON object: {"decision":"ESCALATE","error_class":"OTHER","reason":""}
}

}
