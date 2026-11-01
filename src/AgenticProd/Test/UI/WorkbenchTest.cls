/// Workbench endpoints: Library, production map and the /agenticprod web app over HTTP. No LLM.
/// The HTTP tests need Setup.DashboardSetup to have run.
Class AgenticProd.Test.UI.WorkbenchTest Extends AgenticProd.Test.Case
{

Method TestProductionsListed()
{
	Set tList = ##class(AgenticProd.UI.Workbench).Productions()
	Do $$$AssertTrue(tList.%Size() > 0, "at least one Interoperability namespace")
	Set tHome = $NAMESPACE, tFound = 0
	Set tIter = tList.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		If tRow.namespace = tHome {
			Set tPIter = tRow.productions.%GetIterator()
			While tPIter.%GetNext(, .tP) { Set:tP.name="AgenticProd.Production" tFound = 1 }
		}
	}
	Do $$$AssertTrue(tFound, "the home production is listed")
	Do $$$AssertTrue(##class(AgenticProd.UI.Workbench).KnownNs(tHome))
	Do $$$AssertEquals(##class(AgenticProd.UI.Workbench).KnownNs("%SYS"), 0, "system namespace is not offered")
}

Method TestProductionMap()
{
	Set tProd = ##class(AgenticProd.UI.Workbench).Production($NAMESPACE, "AgenticProd.Production")
	Do $$$AssertTrue($IsObject(tProd), "production opens")
	Do $$$AssertEquals(tProd.totalItems, tProd.items.%Size())
	Set tHasOp = 0, tTriage = 0, tIter = tProd.items.%GetIterator()
	While tIter.%GetNext(, .tItem) {
		Do $$$AssertTrue(tItem.%IsDefined("errors24h") && tItem.%IsDefined("in24h") && tItem.%IsDefined("suspended"), tItem.name_" has 24 h numbers")
		Set:tItem.type="operation" tHasOp = 1
		Set:tItem.checks tTriage = tTriage + 1
	}
	Do $$$AssertTrue(tHasOp, "an operation is typed as operation")
	Do $$$AssertEquals(tTriage, 1, "Triage is the one item marked as checks around the agent")
	Do $$$AssertEquals(tProd.hosts.%Size(), 1, "one AI Hub host")
	Do $$$AssertEquals(tProd.aiItems, 1, "one of the items uses AI Hub")
	Set tHost = tProd.hosts.%Get(0), tKinds = ","
	Do $$$AssertEquals(tHost.agentClass, "AgenticProd.Agent.TriageAgent")
	Set tIter = tHost.components.%GetIterator()
	While tIter.%GetNext(, .tC) { Set tKinds = tKinds_tC.kind_"," }
	For tKind = "model", "toolset", "skill", "knowledge", "policy" {
		Do $$$AssertTrue(tKinds [ (","_tKind_","), "host has a "_tKind_" component")
	}
	Do $$$AssertTrue(tHost.components.%Get(0).sub [ "key:", "model circle says where the key comes from")
	Do $$$AssertTrue(tProd.usage24h.%IsDefined("runs") && tProd.usage24h.%IsDefined("denied") && tProd.usage24h.%IsDefined("costUsd"), "24 h totals")
	Do $$$AssertEquals(##class(AgenticProd.UI.Workbench).Production($NAMESPACE, "No.Such.Production"), "", "unknown production")
}

Method TestLibrary()
{
	Set tLib = ##class(AgenticProd.UI.Workbench).Library()
	Set tAll = ","
	For tKey = "agents", "toolsets", "skills", "policies", "knowledge", "checks" {
		Set tIter = $PROPERTY(tLib, tKey).%GetIterator()
		Do $$$AssertTrue($PROPERTY(tLib, tKey).%Size() > 0, tKey_" is not empty")
		While tIter.%GetNext(, .tRow) {
			Set tAll = tAll_tRow.class_","
			Do $$$AssertTrue(tRow.name '= "" && (tRow.description '= ""), tRow.class_" has a name and a description")
		}
	}
	Do $$$AssertTrue(tAll [ ",AgenticProd.Agent.TriageAgent,", "triage agent")
	Do $$$AssertTrue(tAll [ ",AgenticProd.Skill.HL7Repair,", "skill")
	Do $$$AssertTrue(tAll [ ",AgenticProd.Policy.ReadOnly,", "authorization policy")
	Do $$$AssertTrue(tAll [ ",AgenticProd.Policy.Audit,", "audit policy")
	Do $$$AssertEquals(tAll [ "PingAgent", 0, "ping agent is hidden")
	Do $$$AssertEquals(tAll [ "AgenticProd.Agent.Base,", 0, "agent base is hidden")
	Do $$$AssertEquals(tAll [ ".Test.", 0, "test classes are hidden")
	Do $$$AssertEquals(tAll [ ",%AI.", 0, "AI Hub's own classes are not listed")
	// Skills extend ToolSet; they must not appear twice
	Set tIter = tLib.toolsets.%GetIterator()
	While tIter.%GetNext(, .tT) { Do $$$AssertEquals(tT.class [ ".Skill.", 0, tT.class_" is a tool set, not a skill") }
	Set tBase = tLib.toolsets.%Get(0)
	Do $$$AssertTrue(tBase.tools.%Size() = tBase.toolDescriptions.%Size() && (tBase.tools.%Size() > 0), "tool names come with descriptions")
	Set tIter = tLib.checks.%GetIterator()
	While tIter.%GetNext(, .tC) { Do $$$AssertTrue(tC.plain, tC.name_" is marked plain IRIS") }
	Do $$$AssertTrue(tBase.usedBy [ "TriageAgent", "toolset says who uses it")
}

Method TestOwnProductions()
{
	// A package mapped in from another database is not that namespace's production
	Quit:'##class(%SYS.Namespace).Exists("LEGACY")
	Set tRow = ##class(AgenticProd.UI.Workbench).NamespaceRow("LEGACY")
	Set tNames = ",", tIter = tRow.productions.%GetIterator()
	While tIter.%GetNext(, .tP) { Set tNames = tNames_tP.name_"," }
	Do $$$AssertTrue(tNames [ ",Legacy.OrdersProduction,", "LEGACY lists its own production")
	Do $$$AssertEquals(tNames [ ",AgenticProd.Production,", 0, "IRISAPP production is not listed under LEGACY")
	Set tProd = ##class(AgenticProd.UI.Workbench).Production("LEGACY", "Legacy.OrdersProduction")
	Do $$$AssertEquals(tProd.name, "Legacy.OrdersProduction", "map reads the production asked for")
	Do $$$AssertEquals(tProd.namespace, "LEGACY")
	For tTo = "BillingOut", "LabelPrinter", "LabOrdersOut", "ResultsOut" {
		Do $$$AssertTrue(..HasLink(tProd, "OrdersRouter", tTo), "OrdersRouter -> "_tTo)
	}
}

Method TestIrisappLinks()
{
	Set tProd = ##class(AgenticProd.UI.Workbench).Production($NAMESPACE, "AgenticProd.Production")
	Do $$$AssertTrue(..HasLink(tProd, "LabRouter", "EhrOut"), "LabRouter -> EhrOut")
	Do $$$AssertTrue(..HasLink(tProd, "LabRouter", "FhirOut"), "LabRouter -> FhirOut")
	Set tIter = tProd.items.%GetIterator()
	While tIter.%GetNext(, .tItem) { Do $$$AssertTrue(tItem.%IsDefined("sent24h"), tItem.name_" has sent24h") }
}

ClassMethod HasLink(pProd As %DynamicObject, pFrom As %String, pTo As %String) As %Boolean [ Internal ]
{
	Set tIter = pProd.connections.%GetIterator()
	Set tFound = 0
	While tIter.%GetNext(, .tC) { Set:(tC.from=pFrom)&&(tC.to=pTo) tFound = 1 }
	Quit tFound
}

Method TestSource()
{
	Set tOut = ##class(AgenticProd.UI.Workbench).Source("AgenticProd.Policy.Audit")
	Do $$$AssertTrue($IsObject(tOut) && (tOut.source [ "Class AgenticProd.Policy.Audit"), "source of a Library class")
	Do $$$AssertEquals(##class(AgenticProd.UI.Workbench).Source("Ens.Director"), "", "other classes are not served")
	Do $$$AssertEquals(##class(AgenticProd.UI.Workbench).Source(""), "")
}

Method TestHttp()
{
	Set tUser = ##class(AgenticProd.Setup).#REVIEWUSER, tPass = ##class(AgenticProd.Setup).#REVIEWPASSWORD
	Set tNs = $NAMESPACE
	Set tReq = ..Get("api/workbench/productions", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "productions")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.productions.%Size() > 0)
	Set tReq = ..Get("api/workbench/production?ns="_tNs_"&name=AgenticProd.Production", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "production")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.items.%Size() > 0)
	Do $$$AssertEquals(tJSON.hosts.%Size(), 1, "host with its components over HTTP")
	Do $$$AssertEquals(..Get("api/workbench/production?ns="_tNs_"&name=No.Such", tUser, tPass).HttpResponse.StatusCode, 404)
	Do $$$AssertEquals(..Get("api/workbench/production?ns=%25SYS&name=X", tUser, tPass).HttpResponse.StatusCode, 400, "namespace not offered")
	Do $$$AssertEquals(..Get("api/workbench/production", tUser, tPass).HttpResponse.StatusCode, 400, "missing params")
	Set tReq = ..Get("api/workbench/library", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "library")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.agents.%Size() > 0 && (tJSON.toolsets.%Size() > 0), "library has agents and tools for the reviewer role")
	Set tReq = ..Get("api/workbench/source?class=AgenticProd.Policy.Audit", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "source")
	Do $$$AssertTrue(##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data).source [ "Class AgenticProd.Policy.Audit", "source text arrives")
	Do $$$AssertEquals(..Get("api/workbench/source?class=Ens.Director", tUser, tPass).HttpResponse.StatusCode, 404, "other classes are refused")
	Do $$$AssertEquals(..Get("api/workbench/source", tUser, tPass).HttpResponse.StatusCode, 404, "no class")
	Do $$$AssertEquals(..Get("workbench.js", tUser, tPass).HttpResponse.StatusCode, 200, "workbench script")
	Do $$$AssertEquals(..Get("workbench.css", tUser, tPass).HttpResponse.StatusCode, 200, "workbench styles")
	Do $$$AssertEquals(..Get("api/workbench/library").HttpResponse.StatusCode, 401, "no login")
	Do $$$AssertEquals(..Get("api/studio/catalog", tUser, tPass).HttpResponse.StatusCode, 404, "studio endpoints are gone")
}

Method Get(pPath As %String, pUser As %String = "", pPass As %String = "") As %Net.HttpRequest
{
	Set tReq = ##class(%Net.HttpRequest).%New()
	Set tReq.Server = "localhost", tReq.Port = 52773
	Set:pUser'="" tReq.Username = pUser, tReq.Password = pPass
	Do $$$AssertStatusOK(tReq.Get(##class(AgenticProd.Setup).#DASHAPP_"/"_pPath), "GET "_pPath)
	Quit tReq
}

}
