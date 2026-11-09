/// Add to production: plan checks, the three ways, refusal on a name clash, Remove taking out
/// exactly the added items, and the dialog endpoint entry. Works on ScratchProd, which is not
/// running, so nothing is restarted. No LLM.
Class AgenticProd.Test.Plugin.AddAgentTest Extends AgenticProd.Test.Case
{

Parameter PROD = "AgenticProd.Test.Plugin.ScratchProd";

Parameter AGENT = "AgenticProd.Agent.TriageAgent";

/// Workflow role the failure way creates; a fresh name per run, since a role with members is not deleted.
Property Role As %String [ InitialExpression = {"WbTestRole"_($ZHOROLOG # 100000 \ 1)} ];

Method OnBeforeAllTests() As %Status
{
	Do ..Cleanup()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(..Role)
	Do ..Cleanup()
	Quit $$$OK
}

/// Production back to its class text, tracking rows and the test role gone.
ClassMethod Cleanup()
{
	&sql(DELETE FROM AgenticProd_Data.PluginItem WHERE Production = 'AgenticProd.Test.Plugin.ScratchProd')
	Set tProd = ##class(Ens.Config.Production).LoadFromClass(..#PROD)
	If $IsObject(tProd) {
		Do tProd.%Save()
		Do tProd.SaveToClass()
	}
	Do $SYSTEM.OBJ.Compile(..#PROD, "-d")
}

Method Spec(pName As %String = "WbTestAgent", pWay As %String = "failure") As %DynamicObject
{
	Quit {"agentClass":(..#AGENT), "namespace":($NAMESPACE), "production":(..#PROD), "name":(pName), "way":(pWay),
		"watch":["ScratchOut"], "mode":"propose", "role":"", "roleNew":(..Role)}
}

Method ItemNames() As %String
{
	Set tProd = ##class(Ens.Config.Production).%OpenId(..#PROD)
	Set:'$IsObject(tProd) tProd = ##class(Ens.Config.Production).LoadFromClass(..#PROD)
	Set tOut = ""
	For i = 1:1:tProd.Items.Count() Set tOut = tOut_$SELECT(tOut '= "": ",", 1: "")_tProd.Items.GetAt(i).Name
	Quit tOut
}

Method Setting(pItem As %String, pName As %String) As %String
{
	Set tProd = ##class(Ens.Config.Production).%OpenId(..#PROD)
	Set tItem = tProd.FindItemByConfigName(pItem)
	Quit:'$IsObject(tItem) ""
	Quit:tItem.GetSetting(pName, .tValue) tValue
	Quit ""
}

Method TestPlanChecks()
{
	Set tPlan = ##class(AgenticProd.Plugin.AddAgent).Plan(..Spec("1bad"))
	Do $$$AssertNotTrue(tPlan.ok, "name must start with a letter")
	Set tSpec = ..Spec()
	Set tSpec.watch = []
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.AddAgent).Plan(tSpec).ok, "failure way needs something to watch")
	Set tSpec = ..Spec(, "somewhere")
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.AddAgent).Plan(tSpec).ok, "unknown way")
	Set tSpec = ..Spec("ScratchOut", "process")
	Set tPlan = ##class(AgenticProd.Plugin.AddAgent).Plan(tSpec)
	Do $$$AssertNotTrue(tPlan.ok, "an existing item name is refused")
	Do $$$AssertTrue(tPlan.errors.%Get(0) [ "already has an item named ScratchOut", tPlan.errors.%Get(0))
	Set tPlan = ##class(AgenticProd.Plugin.AddAgent).Plan(..Spec())
	Do $$$AssertTrue(tPlan.ok, tPlan.errors.%ToJSON())
	Do $$$AssertEquals(tPlan.items.%Size(), 4, "host, watch, check, workflow role")
	Set tPlan = ##class(AgenticProd.Plugin.AddAgent).Plan(..Spec("WbTestAgent", "process"))
	Do $$$AssertEquals(tPlan.items.%Size(), 1, "own process: host only")
	Do $$$AssertTrue(tPlan.snippets.objectscript [ "SendRequestSync(""WbTestAgent""", "snippet names the item")
	Do $$$AssertTrue(tPlan.snippets.bpl [ "target=""WbTestAgent""", "BPL snippet names the item")
	Do $$$AssertEquals(..ItemNames(), "ScratchOut", "planning changes nothing")
}

Method TestFailureWayNeedsTheAnswerFormat()
{
	Do $$$AssertTrue(##class(AgenticProd.Plugin.AddAgent).ContractReady(..#AGENT), "triage agent has it")
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.AddAgent).ContractReady("AgenticProd.Agent.PingAgent"), "ping agent has none")
	Set tSpec = ..Spec()
	Set tSpec.agentClass = "AgenticProd.Agent.PingAgent"
	Set tPlan = ##class(AgenticProd.Plugin.AddAgent).Plan(tSpec)
	Do $$$AssertNotTrue(tPlan.ok, "failure way refused without the answer format")
	Do $$$AssertTrue(tPlan.errors.%Get(0) [ "answer format")
	Set tSpec.way = "process"
	Do $$$AssertTrue(##class(AgenticProd.Plugin.AddAgent).Plan(tSpec).ok, "own process still allowed")
	Do $$$AssertTrue(##class(AgenticProd.Plugin.AddAgent).Watchable($NAMESPACE, ..#PROD, ..#AGENT).canFail)
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.AddAgent).Watchable($NAMESPACE, ..#PROD, "AgenticProd.Agent.PingAgent").canFail)
}

Method TestWatchableListsItemsNotOwnClasses()
{
	Set tOut = ##class(AgenticProd.Plugin.AddAgent).Watchable($NAMESPACE, ..#PROD)
	Do $$$AssertEquals(tOut.items.%Size(), 1)
	Do $$$AssertEquals(tOut.items.%Get(0).name, "ScratchOut")
	Do $$$AssertEquals(tOut.items.%Get(0).type, "operation")
	Do $$$AssertTrue(tOut.%IsDefined("roles"))
}

Method TestFailureWayAddsFourItemsAndRemoveTakesThemOut()
{
	Set tAdd = ##class(AgenticProd.Plugin.AddAgent).Apply(..Spec())
	Do $$$AssertTrue(tAdd.ok, tAdd.errors.%ToJSON())
	Do $$$AssertEquals(..ItemNames(), "ScratchOut,WbTestAgent,WbTestAgentWatch,WbTestAgentCheck,"_..Role)
	Do $$$AssertEquals(..Setting("WbTestAgent", "AgentClass"), ..#AGENT, "installer sets AgentClass on the host")
	Do $$$AssertEquals(..Setting("WbTestAgentWatch", "WatchItems"), "ScratchOut")
	Do $$$AssertEquals(..Setting("WbTestAgentWatch", "OwnPrefix"), "WbTestAgent")
	Do $$$AssertEquals(..Setting("WbTestAgentWatch", "TargetConfigName"), "WbTestAgentCheck")
	Do $$$AssertEquals(..Setting("WbTestAgentCheck", "AgentTarget"), "WbTestAgent")
	Do $$$AssertEquals(..Setting("WbTestAgentCheck", "ApprovalTarget"), ..Role)
	Do $$$AssertEquals(..Setting("WbTestAgentCheck", "ActionMode"), "propose")
	Do $$$AssertEquals(..Setting("ScratchOut", "FilePath"), "/tmp/", "the existing item keeps its settings")

	Set tInstalls = ##class(AgenticProd.Plugin.AddAgent).Installs(..#AGENT, $NAMESPACE, ..#PROD)
	Do $$$AssertEquals(tInstalls.%Size(), 1)
	Do $$$AssertEquals(tInstalls.%Get(0).items.%Size(), 4)
	Do $$$AssertEquals(tInstalls.%Get(0).way, "failure")
	Do $$$AssertEquals(tInstalls.%Get(0).mode, "propose", "failure way reports its action mode")
	// The AI.* plug-in lists must not see this install
	Set tRows = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.PluginItem WHERE Production = ? AND (Owner IS NULL OR Owner = '')", ..#PROD).%Get(0)
	Do $$$AssertEquals(+tRows.N, 0)

	Set tAgain = ##class(AgenticProd.Plugin.AddAgent).Apply(..Spec())
	Do $$$AssertNotTrue(tAgain.ok, "same name again is refused")
	Do $$$AssertEquals(..ItemNames(), "ScratchOut,WbTestAgent,WbTestAgentWatch,WbTestAgentCheck,"_..Role, "nothing changed by the refusal")

	Set tGone = ##class(AgenticProd.Plugin.AddAgent).Remove($NAMESPACE, ..#PROD, "WbTestAgent")
	Do $$$AssertTrue(tGone.ok, tGone.errors.%ToJSON())
	Do $$$AssertEquals(tGone.removed.%Size(), 4)
	Do $$$AssertEquals(..ItemNames(), "ScratchOut", "only the added items are gone")
	Do $$$AssertEquals(##class(AgenticProd.Plugin.AddAgent).Installs(..#AGENT, $NAMESPACE, ..#PROD).%Size(), 0)
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.AddAgent).Remove($NAMESPACE, ..#PROD, "WbTestAgent").ok, "second Remove finds nothing")
}

/// An agent with no skills used to break the production map with <INVALID OREF>.
Method TestMapLoadsAgentWithoutSkillsAndAfterRemove()
{
	Set tBefore = ##class(AgenticProd.UI.Workbench).Production($NAMESPACE, ..#PROD)
	Set tSpec = ..Spec("WbNoSkill")
	Set tSpec.agentClass = "AgenticProd.Test.Plugin.NoSkillAgent"
	Set tAdd = ##class(AgenticProd.Plugin.AddAgent).Apply(tSpec)
	Do $$$AssertTrue(tAdd.ok, tAdd.errors.%ToJSON())
	Set tMap = ##class(AgenticProd.UI.Workbench).Production($NAMESPACE, ..#PROD)
	Do $$$AssertEquals(tMap.items.%Size(), tBefore.items.%Size() + 4, "the four added items are listed")
	Do $$$AssertEquals(tMap.hosts.%Size(), 1, "the new host is listed")
	Do $$$AssertEquals(tMap.hosts.%Get(0).agentClass, "AgenticProd.Test.Plugin.NoSkillAgent")
	Do $$$AssertEquals(tMap.installs.%Size(), 1, "the install is listed")
	Set tIter = tMap.items.%GetIterator(), tNotes = 0
	While tIter.%GetNext(, .tRow) { Set:tRow.note'="" tNotes = tNotes + 1 }
	Do $$$AssertEquals(tNotes, 0, "no item is reported as unreadable")

	Do $$$AssertTrue(##class(AgenticProd.Plugin.AddAgent).Remove($NAMESPACE, ..#PROD, "WbNoSkill").ok)
	Set tAfter = ##class(AgenticProd.UI.Workbench).Production($NAMESPACE, ..#PROD)
	Do $$$AssertEquals(tAfter.items.%Size(), tBefore.items.%Size(), "back to the original items")
	Do $$$AssertEquals(tAfter.hosts.%Size(), tBefore.hosts.%Size())
	Do $$$AssertEquals(tAfter.installs.%Size(), 0)
}

/// The Messages filter lists a production that only got an Add to production install. Uses a
/// made-up namespace with a tracking row, so no live production is touched.
Method TestInstallMakesNamespaceActive()
{
	Set tNs = "ZZNOINSTALL"
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.Installer).Active(tNs, 0), "nothing there yet")
	Do $$$AssertTrue(##class(AgenticProd.Plugin.Installer).Active(tNs, 1), "enabled plug-in is active")
	Set tRow = ##class(AgenticProd.Data.PluginItem).%New()
	Set tRow.Namespace = tNs, tRow.Production = "Zz.Prod", tRow.ItemName = "WbTestAgent", tRow.Owner = "WbTestAgent", tRow.AgentClass = ..#AGENT, tRow.Mode = "process"
	Do $$$AssertStatusOK(tRow.%Save())
	Do $$$AssertTrue(##class(AgenticProd.Plugin.Installer).Active(tNs, 0), "an install makes it active")
	Do ##class(AgenticProd.Data.PluginItem).%DeleteId(tRow.%Id())
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.Installer).Active(tNs, 0), "gone again after the row is removed")
	// Real list: every row carries the flag, and LEGACY (installs and decisions) is active
	Set tIter = ##class(AgenticProd.Plugin.Installer).Productions().%GetIterator(), tHome = 0
	While tIter.%GetNext(, .tP) { Do $$$AssertTrue(tP.%IsDefined("active"), "active on "_tP.namespace)  Set:tP.native tHome = tP.active }
	Do $$$AssertTrue(tHome, "home production is active")
}

Method TestProcessWayAddsOnlyTheHost()
{
	Set tAdd = ##class(AgenticProd.Plugin.AddAgent).Apply(..Spec("WbTestAgent", "process"))
	Do $$$AssertTrue(tAdd.ok, tAdd.errors.%ToJSON())
	Do $$$AssertEquals(..ItemNames(), "ScratchOut,WbTestAgent")
	Do $$$AssertEquals(##class(AgenticProd.Plugin.AddAgent).Installs(..#AGENT, $NAMESPACE, ..#PROD).%Get(0).way, "process")
	Do $$$AssertEquals(##class(AgenticProd.Plugin.AddAgent).Installs(..#AGENT, $NAMESPACE, ..#PROD).%Get(0).mode, "", "other ways have no mode")
	Do $$$AssertTrue(##class(AgenticProd.Plugin.AddAgent).Remove($NAMESPACE, ..#PROD, "WbTestAgent").ok)
	Do $$$AssertEquals(..ItemNames(), "ScratchOut")
}

Method TestHandleNeedsAdmin()
{
	Set tRes = ##class(AgenticProd.Plugin.AddAgent).Handle("plan", ..Spec(), 0)
	Do $$$AssertEquals(tRes.status, 403)
	Set tRes = ##class(AgenticProd.Plugin.AddAgent).Handle("plan", ..Spec(), 1)
	Do $$$AssertEquals(tRes.status, 200)
	Do $$$AssertTrue(tRes.ok, tRes.errors.%ToJSON())
	Do $$$AssertEquals(##class(AgenticProd.Plugin.AddAgent).Handle("nothing", ..Spec(), 1).status, 400)
	Do $$$AssertEquals(..ItemNames(), "ScratchOut", "plan through the endpoint changes nothing")
}

/// Watch list: only failures that touch a watched item are handed on.
Method TestSentinelWatchList()
{
	Do $$$AssertTrue(##class(AgenticProd.Plugin.SentinelAdapter).IsWatched("BillingOut", "BillingOut, OrdersRouter"))
	Do $$$AssertTrue(##class(AgenticProd.Plugin.SentinelAdapter).IsWatched("OrdersRouter", "BillingOut, OrdersRouter"))
	Do $$$AssertNotTrue(##class(AgenticProd.Plugin.SentinelAdapter).IsWatched("LabelPrinter", "BillingOut,OrdersRouter"))
}

}
