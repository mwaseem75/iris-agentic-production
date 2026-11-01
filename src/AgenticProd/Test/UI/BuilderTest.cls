/// Workbench builders: generate, validate, save, tool test and policy test. No LLM.
/// Saved test classes live under MyAI.WbTest and are deleted again.
Class AgenticProd.Test.UI.BuilderTest Extends AgenticProd.Test.Case
{

Parameter PKG = "MyAI.WbTest";

Method OnAfterAllTests() As %Status
{
	Do $SYSTEM.OBJ.DeletePackage(..#PKG, "-d")
	Quit $$$OK
}

ClassMethod ToolSpec() As %DynamicObject
{
	Quit {"class":"MyAI.WbTest.Queue", "tool":"get_queue_status", "maxRows":20,
		"description":"Show how many messages are waiting for one production item and the oldest one.",
		"args":[{"name":"itemName", "type":"%String", "required":true}],
		"sql":"SELECT COUNT(*) AS Waiting FROM Ens.MessageHeader WHERE TargetConfigName = :itemName AND Status = 'Queued'"}
}

ClassMethod PolicySpec() As %DynamicObject
{
	Quit {"class":"MyAI.WbTest.Protect", "tools":["get_segment"], "message":"Patient identity is protected. Escalate instead.",
		"rules":[{"arg":"segmentRef", "op":"equals", "value":"PID"}, {"arg":"fixJSON", "op":"contains", "value":"PID(1):3"}, {"arg":"note", "op":"starts with", "value":"ab"}]}
}

Method TestGenerateTool()
{
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("tool", ..ToolSpec())
	Do $$$AssertEquals(tGen.errors.%Size(), 0, "tool spec is acceptable")
	Do $$$AssertTrue(tGen.code [ "Extends %AI.ToolSet", "extends ToolSet")
	Do $$$AssertTrue(tGen.code [ "<Query Name=""get_queue_status""", "query tool")
	Do $$$AssertTrue(tGen.code [ "Arguments=""itemName As %String""", "arguments")
	Do $$$AssertTrue(tGen.code [ "MaxRows=""20""", "max rows")
	Do $$$AssertTrue(tGen.code [ "XData BuilderSpec", "form values travel with the class")
}

Method TestSqlRules()
{
	Set tSpec = ..ToolSpec()
	For tSql = "DELETE FROM Ens.MessageHeader", "SELECT 1; SELECT 2", "SELECT * FROM A WHERE x = :nope", "SELECT 1 -- comment", "SELECT a INTO :b FROM c", "UPDATE x SET y = 1", "SELECT * FROM A WHERE x = ?" {
		Set tSpec.sql = tSql
		Do $$$AssertTrue(##class(AgenticProd.UI.Builder).Generate("tool", tSpec).errors.%Size() > 0, "refused: "_tSql)
	}
	// Words inside a string literal are data, not statements
	Set tSpec.sql = "SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE TargetConfigName = :itemName AND Status = 'delete update'"
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Generate("tool", tSpec).errors.%Size(), 0, "literal text is not scanned")
	Set tSpec.sql = "SELECT 1 FROM Ens.MessageHeader WHERE TargetConfigName = :itemName;"
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Generate("tool", tSpec).errors.%Size(), 0, "one trailing semicolon is dropped")
}

Method TestClassNames()
{
	Set tSpec = ..ToolSpec()
	For tName = "AgenticProd.Tools.Evil", "Queue", "MyAI.Queue", "MyAI.Tools.9x", "MyAI.Tools.A-B", "MyAI..X", "" {
		Set tSpec.class = tName
		Do $$$AssertTrue(##class(AgenticProd.UI.Builder).Generate("tool", tSpec).errors.%Size() > 0, "refused: '"_tName_"'")
	}
}

Method TestGeneratePolicySkillAgent()
{
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("policy", ..PolicySpec())
	Do $$$AssertEquals(tGen.errors.%Size(), 0)
	Do $$$AssertTrue(tGen.code [ "Extends AgenticProd.Policy.ReadOnly", "extends ReadOnly")
	Do $$$AssertTrue(tGen.code [ "##super(toolref, call, metadata)", "calls ##super first")
	Do $$$AssertTrue(tGen.code [ "$$$AICoreToolAccessDenied", "deny message")
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("skill", {"class":"MyAI.WbTest.Skill", "name":"queue-check", "description":"Load when a target may be down before RESEND.", "instructions":("# Queue check"_$CHAR(10)_"1. Call the tool."), "tools":["AgenticProd.Tools.Base"]})
	Do $$$AssertEquals(tGen.errors.%Size(), 0, tGen.errors.%ToJSON())
	Do $$$AssertTrue(tGen.code [ "Extends %AI.Agent.Skill", "skill base")
	Do $$$AssertTrue(tGen.code [ "name: queue-check", "SUMMARY name")
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("skill", {"class":"MyAI.WbTest.Skill", "name":"queue-check", "description":"Load when a target may be down before RESEND.", "instructions":("# Queue check"_$CHAR(10)_"1. Call the tool."), "tools":["No.Such.Tools"]})
	Do $$$AssertTrue(tGen.errors.%Size() > 0, "unknown tool class refused")
	Set tAgent = {"class":"MyAI.WbTest.Agent", "providerConfig":"openai_main", "model":"gpt-4o-mini", "toolsets":["AgenticProd.Tools.Base"], "skills":["AgenticProd.Skill.CodeMapping"], "authPolicy":"AgenticProd.Policy.ReadOnly", "auditPolicy":"AgenticProd.Policy.Audit", "instructions":"You triage failed order messages. Read the error first."}
	Set tGen = ##class(AgenticProd.UI.Builder).Generate("agent", tAgent)
	Do $$$AssertEquals(tGen.errors.%Size(), 0, tGen.errors.%ToJSON())
	Do $$$AssertTrue(tGen.code [ "Extends AgenticProd.Agent.Base", "agent base")
	Do $$$AssertTrue(tGen.code [ "Parameter AUTHPOLICY = ""AgenticProd.Policy.ReadOnly""", "auth policy")
	Set tAgent.authPolicy = "AgenticProd.Policy.Audit"
	Do $$$AssertTrue(##class(AgenticProd.UI.Builder).Generate("agent", tAgent).errors.%Size() > 0, "audit class is not an authorization policy")
}

Method TestValidateSavesNothing()
{
	Set tSpec = ..ToolSpec(), tSpec.class = "MyAI.WbTest.Scratch"
	Set tRes = ##class(AgenticProd.UI.Builder).Validate("tool", tSpec)
	Do $$$AssertEquals(tRes.ok, 1, tRes.errors.%ToJSON())
	Do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%ExistsId(tSpec.class), 0, "validate left no class behind")
	Set tBad = ##class(AgenticProd.UI.Builder).Validate("tool", {"class":"MyAI.WbTest.Bad", "tool":"t", "maxRows":5, "description":"A tool with a statement that is not a select.", "args":[], "sql":"DROP TABLE x"})
	Do $$$AssertEquals(tBad.ok, 0)
	Do $$$AssertTrue(tBad.errors.%Size() > 0, "errors listed")
}

Method TestSaveAndReopen()
{
	Set tSpec = ..ToolSpec()
	Set tRes = ##class(AgenticProd.UI.Builder).Save("tool", tSpec)
	Do $$$AssertEquals(tRes.saved, 1, tRes.errors.%ToJSON())
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(tSpec.class), "class compiled")
	Set tOpen = ##class(AgenticProd.UI.Builder).OpenSpec(tSpec.class)
	Do $$$AssertTrue($IsObject(tOpen), "form values reopen")
	Do $$$AssertEquals(tOpen.tool, "get_queue_status")
	// The Library shows it with its tool and description
	Set tInfo = ##class(AgenticProd.UI.Workbench).ToolSetInfo(tSpec.class)
	Do $$$AssertEquals(tInfo.tools.%Get(0), "get_queue_status", "Library reads <Query> tools")
	Do $$$AssertTrue(tInfo.description '= "", "Library has a description")
	// Saving again updates; a different kind on the same name is refused
	Set tSpec.maxRows = 5
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Save("tool", tSpec).saved, 1, "edit saves")
	Set tClash = ..PolicySpec(), tClash.class = tSpec.class
	Set tRes = ##class(AgenticProd.UI.Builder).Save("policy", tClash)
	Do $$$AssertEquals(tRes.saved, 0, "other kind refused")
	// A class nobody built here is never overwritten
	Set tSC = ##class(AgenticProd.UI.Builder).Compile("MyAI.WbTest.ByHand", "Class MyAI.WbTest.ByHand Extends %RegisteredObject {}"_$CHAR(10))
	Do $$$AssertStatusOK(tSC)
	Set tHand = ..ToolSpec(), tHand.class = "MyAI.WbTest.ByHand"
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Save("tool", tHand).saved, 0, "hand-written class is kept")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).OpenSpec("MyAI.WbTest.ByHand"), "", "no form values for it")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).OpenSpec("AgenticProd.Policy.ReadOnly"), "", "only MyAI classes open")
}

Method TestToolRuns()
{
	Set tRes = ##class(AgenticProd.UI.Builder).TestTool(..ToolSpec(), {"itemName":"NoSuchItem"})
	Do $$$AssertEquals(tRes.ok, 1, tRes.errors.%ToJSON())
	Set tJson = {}.%FromJSON(tRes.result)
	Do $$$AssertEquals(tJson."row_count", 1)
	Do $$$AssertEquals(tJson.rows.%Get(0).Waiting, 0, "no such item waits")
}

Method TestPolicyAllowsAndDenies()
{
	Set tDeny = ##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "get_segment", {"segmentRef":"pid"})
	Do $$$AssertEquals(tDeny.ok, 1, tDeny.errors.%ToJSON())
	Do $$$AssertEquals(tDeny.allowed, 0, "equals is case-insensitive")
	Do $$$AssertTrue(tDeny.message [ "Patient identity is protected", "deny message returned")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "get_segment", {"segmentRef":"OBX(1)"}).allowed, 1)
	Set tFix = "[{""path"":""PID(1):3""}]"
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "get_segment", {"fixJSON":(tFix)}).allowed, 0, "contains")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "get_segment", {"note":"ABCD"}).allowed, 0, "starts with")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "get_segment", {"note":"xab"}).allowed, 1, "starts with is not contains")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).TestPolicy(..PolicySpec(), "other_tool", {"segmentRef":"PID"}).allowed, 1, "rules apply to the chosen tools only")
}

Method TestAdminOnly()
{
	Set tBody = {"kind":"tool", "spec":(..ToolSpec())}
	For tAction = "generate", "validate", "save", "test-tool", "test-policy" {
		Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Handle(tAction, tBody, 0).status, 403, tAction_" refused for a non-admin")
	}
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Handle("generate", {"kind":"tool"}, 1).status, 400, "spec is required")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Handle("nope", tBody, 1).status, 400, "unknown action")
	Do $$$AssertEquals(##class(AgenticProd.UI.Builder).Handle("generate", tBody, 1).status, 200)
}

/// Base attaches AUTHPOLICY/AUDITPOLICY in %OnInit unless a policy is already set.
Method TestAgentBaseAttachesPolicies()
{
	Set tAgent = {"class":"MyAI.WbTest.Agent", "providerConfig":"openai_main", "model":"gpt-4o-mini", "toolsets":["AgenticProd.Tools.Base"], "skills":[], "authPolicy":"AgenticProd.Policy.ReadOnly", "auditPolicy":"AgenticProd.Policy.Audit", "instructions":"You triage failed order messages. Read the error first."}
	Set tRes = ##class(AgenticProd.UI.Builder).Save("agent", tAgent)
	Do $$$AssertEquals(tRes.saved, 1, tRes.errors.%ToJSON())
	Set tObj = $CLASSMETHOD("MyAI.WbTest.Agent", "%New")
	Do $$$AssertStatusOK(tObj.%OnInit())
	Do $$$AssertEquals($IsObject(tObj.ToolManager.AuthPolicy) && tObj.ToolManager.AuthPolicy.%IsA("AgenticProd.Policy.ReadOnly"), 1, "auth policy attached")
	Do $$$AssertEquals($IsObject(tObj.ToolManager.AuditPolicy) && tObj.ToolManager.AuditPolicy.%IsA("AgenticProd.Policy.Audit"), 1, "audit policy attached")
	Set tOther = ##class(AgenticProd.Policy.ReadOnly).%New()
	Set tObj2 = $CLASSMETHOD("MyAI.WbTest.Agent", "%New")
	Do tObj2.ToolManager.SetAuthPolicy(tOther)
	Do $$$AssertStatusOK(tObj2.%OnInit())
	Do $$$AssertTrue(tObj2.ToolManager.AuthPolicy = tOther, "a policy set by the caller is kept")
	Set tTriage = ##class(AgenticProd.Agent.TriageAgent).%New()
	Do $$$AssertStatusOK(tTriage.%OnInit())
	Do $$$AssertEquals($IsObject(tTriage.ToolManager.AuthPolicy), 0, "TriageAgent has no policy parameters, so nothing is attached")
}

}
