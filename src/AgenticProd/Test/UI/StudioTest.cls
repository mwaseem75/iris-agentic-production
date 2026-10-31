/// AI Studio endpoints: data builders and the /agenticprod web app over HTTP. No LLM.
/// The HTTP tests need Setup.DashboardSetup to have run.
Class AgenticProd.Test.UI.StudioTest Extends AgenticProd.Test.Case
{

Method TestProductionsListed()
{
	Set tList = ##class(AgenticProd.UI.Studio).Productions()
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
	Do $$$AssertTrue(##class(AgenticProd.UI.Studio).KnownNs(tHome))
	Do $$$AssertEquals(##class(AgenticProd.UI.Studio).KnownNs("%SYS"), 0, "system namespace is not offered")
}

Method TestProductionItemsAndConnections()
{
	Set tProd = ##class(AgenticProd.UI.Studio).Production($NAMESPACE, "AgenticProd.Production")
	Do $$$AssertTrue($IsObject(tProd), "production opens")
	Do $$$AssertTrue(tProd.items.%Size() > 0, "has items")
	Set tHasOp = 0, tIter = tProd.items.%GetIterator()
	While tIter.%GetNext(, .tItem) {
		Do $$$AssertTrue(tItem.%IsDefined("errors24h") && tItem.%IsDefined("suspended"), tItem.name_" has health")
		Set:tItem.type="operation" tHasOp = 1
	}
	Do $$$AssertTrue(tHasOp, "an operation is typed as operation")
	Do $$$AssertEquals(##class(AgenticProd.UI.Studio).Production($NAMESPACE, "No.Such.Production"), "", "unknown production")
}

Method TestCatalog()
{
	Set tCat = ##class(AgenticProd.UI.Studio).Catalog()
	Set tIds = ""
	Set tIter = tCat.recipes.%GetIterator()
	While tIter.%GetNext(, .tR) { Set tIds = tIds_","_tR.id }
	Do $$$AssertEquals(tIds, ",triage,explain-only,map-codes,resend,blank")
	Do $$$AssertTrue(tCat.toolsets.%Size() >= 3, "toolsets")
	Do $$$AssertTrue(tCat.skills.%Size() >= 1, "skills")
	Do $$$AssertEquals(tCat.comingSoon.%Size(), 2, "classifier and sub-agent are coming soon")
	Do $$$AssertEquals(tCat.memory.%Size(), 2, "memory options")
	Do $$$AssertTrue(tCat.template.tools.%Size() >= 3 && (tCat.template.guardrails.%Size() = 3), "triage template")
	Set tToolsDescribed = 1, tIter = tCat.toolsets.%GetIterator()
	While tIter.%GetNext(, .tT) { Set:tT.description="" tToolsDescribed = 0 }
	Do $$$AssertTrue(tToolsDescribed, "every toolset has a description for the picker")
}

Method TestAgentsListed()
{
	Set tIter = ##class(AgenticProd.UI.Studio).Agents().%GetIterator(), tNames = ""
	While tIter.%GetNext(, .tA) {
		Set tNames = tNames_","_tA.name
		Do $$$AssertTrue(tA.%IsDefined("runsToday") && tA.%IsDefined("costToday"), tA.name_" has today's numbers")
	}
	Do $$$AssertTrue(tNames [ ",TriageAgent", "triage agent is listed")
	Do $$$AssertTrue(tNames '[ ",Base", "the abstract base is not an agent to pick")
}

Method TestDraftRoundTrip()
{
	Set tNs = $NAMESPACE, tName = "Test.StudioDraft"
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.StudioDraft WHERE Production = ?", tName)
	Do $$$AssertTrue(##class(AgenticProd.UI.Studio).Draft(tNs, tName).draft = "", "no draft yet")
	Do $$$AssertStatusOK(##class(AgenticProd.Data.StudioDraft).Put(tNs, tName, {"recipe":"triage"}.%ToJSON()))
	Do $$$AssertStatusOK(##class(AgenticProd.Data.StudioDraft).Put(tNs, tName, {"recipe":"blank"}.%ToJSON()))
	Set tOut = ##class(AgenticProd.UI.Studio).Draft(tNs, tName)
	Do $$$AssertEquals(tOut.draft.recipe, "blank", "last save wins")
	Do $$$AssertEquals(tOut.savedBy, $USERNAME)
	Do $$$AssertTrue($IsObject(##class(AgenticProd.Data.StudioDraft).Find(tNs, tName)))
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM AgenticProd_Data.StudioDraft WHERE Production = ?", tName)
}

Method TestHttp()
{
	Set tUser = ##class(AgenticProd.Setup).#REVIEWUSER, tPass = ##class(AgenticProd.Setup).#REVIEWPASSWORD
	Set tNs = $NAMESPACE
	Set tReq = ..Get("api/studio/productions", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "productions")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.productions.%Size() > 0)
	Do $$$AssertEquals(tJSON.canEdit, 0, "the reviewer cannot edit")
	Set tReq = ..Get("api/studio/production?ns="_tNs_"&name=AgenticProd.Production", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "production")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertTrue(tJSON.items.%Size() > 0)
	Do $$$AssertEquals(..Get("api/studio/production?ns="_tNs_"&name=No.Such", tUser, tPass).HttpResponse.StatusCode, 404)
	Do $$$AssertEquals(..Get("api/studio/production?ns=%25SYS&name=X", tUser, tPass).HttpResponse.StatusCode, 400, "namespace not offered")
	Do $$$AssertEquals(..Get("api/studio/production", tUser, tPass).HttpResponse.StatusCode, 400, "missing params")
	Set tReq = ..Get("api/studio/catalog", tUser, tPass)
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200, "catalog")
	Set tJSON = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
	Do $$$AssertEquals(tJSON.recipes.%Size(), 5)
	Do $$$AssertTrue(tJSON.agents.%Size() > 0, "catalog lists agents")
	Do $$$AssertEquals(..Get("api/studio/draft?ns="_tNs_"&name=AgenticProd.Production", tUser, tPass).HttpResponse.StatusCode, 200, "draft")
	Do $$$AssertEquals(..Get("studio.js", tUser, tPass).HttpResponse.StatusCode, 200, "studio script")
	Do $$$AssertEquals(..Get("studio.css", tUser, tPass).HttpResponse.StatusCode, 200, "studio styles")
	Do $$$AssertEquals(..Get("api/studio/catalog").HttpResponse.StatusCode, 401, "no login")
	// The reviewer is not an admin: saving a draft is refused
	Set tPut = ##class(%Net.HttpRequest).%New()
	Set tPut.Server = "localhost", tPut.Port = 52773, tPut.Username = tUser, tPut.Password = tPass, tPut.ContentType = "application/json"
	Do tPut.EntityBody.Write("{}")
	Do $$$AssertStatusOK(tPut.Put(##class(AgenticProd.Setup).#DASHAPP_"/api/studio/draft?ns="_tNs_"&name=AgenticProd.Production"))
	Do $$$AssertEquals(tPut.HttpResponse.StatusCode, 403, "draft save is admin only")
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
