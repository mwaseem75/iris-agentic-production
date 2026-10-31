Include Ensemble

/// Data behind the AI Studio page. Reads other productions through Ens.Config.Production and
/// the event log; nothing here changes a production.
Class AgenticProd.UI.Studio Extends %RegisteredObject
{

/// System namespaces with productions we never list.
Parameter SKIPNS = "ENSLIB,HSLIB,HSSYS,HSCUSTOM,HSAUX,DOCBOOK";

/// Namespaces with Interoperability, their productions and whether each is running.
ClassMethod Productions() As %DynamicArray
{
	Set tOut = []
	Do ##class(%SYS.Namespace).ListAll(.tList)
	Set tNs = ""
	For {
		Set tNs = $ORDER(tList(tNs))
		Quit:tNs=""
		Continue:($EXTRACT(tNs)="%")||((","_..#SKIPNS_",")[(","_tNs_","))
		// No access to one namespace must not hide the others
		Try {
			Set tRow = ..NamespaceRow(tNs)
			Do:tRow.productions.%Size() tOut.%Push(tRow)
		} Catch {}
	}
	Quit tOut
}

ClassMethod NamespaceRow(pNs As %String) As %DynamicObject [ Internal ]
{
	New $NAMESPACE
	Set tRow = {"namespace":(pNs), "productions":[]}
	Set $NAMESPACE = pNs
	Quit:'##class(%EnsembleMgr).IsEnsembleNamespace(pNs) tRow
	Do ##class(Ens.Director).GetProductionStatus(.tCurrent, .tState)
	// Productions are classes extending Ens.Production directly. The dictionary hides classes
	// from a read-only user in some namespaces, so the current production is always added.
	Set:tCurrent'="" tNames(tCurrent) = ""
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Super [ 'Ens.Production' AND Name NOT LIKE 'Ens%' AND Name NOT LIKE 'HS.%'")
		While tRS.%Next() { Set tNames(tRS.Name) = "" }
	} Catch {}
	Set tName = ""
	For {
		Set tName = $ORDER(tNames(tName))
		Quit:tName=""
		Set tP = {"name":(tName)}
		Do tP.%Set("current", ''(tName = tCurrent), "boolean")
		Do tP.%Set("running", ''((tName = tCurrent) && (tState = $$$eProductionStateRunning)), "boolean")
		Do tRow.productions.%Push(tP)
	}
	Quit tRow
}

/// Items of one production with 24 h health, and the connections between them. Returns ""
/// when the production does not exist.
ClassMethod Production(pNs As %String, pName As %String) As %DynamicObject
{
	// Plug-in rows are in the home namespace; the other namespace may not map our classes
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ItemName, Mode FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ?", pNs, pName)
	While tRS.%Next() { Set tAI(tRS.ItemName) = tRS.Mode }
	Set tNow = $ZTIMESTAMP, tSince = $ZDATETIME((tNow - 1)_","_$PIECE(tNow, ",", 2), 3)
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set tProd = ##class(Ens.Config.Production).%OpenId(pName)
	Set:'$IsObject(tProd) tProd = ##class(Ens.Config.Production).LoadFromClass(pName)
	Quit:'$IsObject(tProd) ""
	Do ##class(Ens.Director).GetProductionStatus(.tCurrent, .tState)
	Set tOut = {"namespace":(pNs), "name":(pName), "items":[], "connections":[]}
	Do tOut.%Set("running", ''((pName = tCurrent) && (tState = $$$eProductionStateRunning)), "boolean")
	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i)
		Set tRow = {"name":(tItem.Name), "class":(tItem.ClassName), "type":(..TypeOf(tItem.ClassName)), "category":(tItem.Category)}
		Do tRow.%Set("enabled", ''tItem.Enabled, "boolean")
		Do tRow.%Set("ai", ''($DATA(tAI(tItem.Name)) || (tItem.ClassName = "AgenticProd.Operation.Agent")), "boolean")
		Set:$DATA(tAI(tItem.Name)) tRow.mode = tAI(tItem.Name)
		Set tHealth = ..ItemHealth(tItem.Name, tSince)
		Set tRow.errors24h = tHealth.errors24h, tRow.suspended = tHealth.suspended, tRow.lastError = tHealth.lastError
		Do tOut.items.%Push(tRow)
		For j = 1:1:tItem.Settings.Count() {
			Set tSet = tItem.Settings.GetAt(j)
			Continue:(tSet.Name '= "TargetConfigName")&&(tSet.Name '= "TargetConfigNames")
			Set tList = $TRANSLATE(tSet.Value, " ", "")
			For k = 1:1:$LENGTH(tList, ",") {
				Set tTo = $PIECE(tList, ",", k)
				Do:tTo'="" tOut.connections.%Push({"from":(tItem.Name), "to":(tTo)})
			}
		}
	}
	Quit tOut
}

/// Errors and suspended messages of one item, read in the current namespace.
ClassMethod ItemHealth(pItem As %String, pSince As %String) As %DynamicObject [ Internal ]
{
	Set tOut = {"errors24h":0, "suspended":0, "lastError":""}
	// Plain SQL: the namespace may not map AgenticProd classes
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 2 AND TimeLogged >= ?", pItem, pSince)
		If tRS.%Next() Set tOut.errors24h = +tRS.%GetData(1)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName = ? AND %EXTERNAL(Status) = 'Suspended'", pItem)
		If tRS.%Next() Set tOut.suspended = +tRS.%GetData(1)
		If tOut.errors24h {
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Text FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 2 AND TimeLogged >= ? ORDER BY ID DESC", pItem, pSince)
			If tRS.%Next() Set tOut.lastError = $EXTRACT(tRS.%GetData(1), 1, 300)
		}
	} Catch {}
	Quit tOut
}

/// service, process, operation or other, from the class hierarchy. PEX and Python items
/// extend the same Ens base classes.
ClassMethod TypeOf(pClass As %String) As %String [ Internal ]
{
	Set tType = "other"
	Try {
		For tBase = "Ens.BusinessService:service", "Ens.BusinessProcess:process", "Ens.BusinessOperation:operation" {
			If $CLASSMETHOD(pClass, "%Extends", $PIECE(tBase, ":")) Set tType = $PIECE(tBase, ":", 2)  Quit
		}
	} Catch {}
	Quit tType
}

/// Recipes, toolsets, skills, knowledge bases, policies, provider configs and Workflow roles
/// the page offers. Read-only; the classifier and sub-agent blocks are not built yet.
ClassMethod Catalog() As %DynamicObject
{
	Set tOut = {"recipes":(..Recipes()), "toolsets":[], "policies":[], "knowledgeBases":[], "roles":[], "comingSoon":["Classifier agent", "Sub-agent"]}
	Set tOut.skills = ##class(AgenticProd.Settings.Store).Skills()
	Set tOut.providers = ##class(AgenticProd.Settings.Store).Providers()
	For tClass = "AgenticProd.Tools.Base", "AgenticProd.Tools.HL7", "AgenticProd.Tools.Mapping" {
		Do tOut.toolsets.%Push({"class":(tClass), "name":($PIECE(tClass, ".", *))})
	}
	For tClass = "AgenticProd.Policy.ReadOnly", "AgenticProd.Policy.Audit", "AgenticProd.Policy.InjectionGuard" {
		Do tOut.policies.%Push({"class":(tClass), "name":($PIECE(tClass, ".", *))})
	}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM EnsLib_Workflow.RoleDefinition ORDER BY Name")
	While tRS.%Next() { Do tOut.roles.%Push(tRS.Name) }
	// Setup builds search_loinc; other knowledge bases are not listed by AI Hub yet
	Do tOut.knowledgeBases.%Push({"name":"search_loinc", "description":"LOINC subset for lab code mapping"})
	Quit tOut
}

/// Each recipe is the triage agent template with a preset mode, skills and toolsets.
ClassMethod Recipes() As %DynamicArray
{
	Set tAll = ["AgenticProd.Tools.Base", "AgenticProd.Tools.HL7", "AgenticProd.Tools.Mapping"]
	Set tRecipes = []
	Do tRecipes.%Push({"id":"triage", "title":"Triage its failures", "recommended":true, "mode":"propose", "icon":"first-aid-kit", "kind":"ai",
		"description":"Sentinel watches errors, the agent finds the cause and proposes a fix, a person approves",
		"skills":["AgenticProd.Skill.HL7Repair"], "toolsets":(tAll), "blocks":["sentinel", "agent", "human"]})
	Do tRecipes.%Push({"id":"explain-only", "title":"Explain failures only", "mode":"observe", "icon":"eye", "kind":"tr",
		"description":"Observe mode: the agent writes an explanation, changes nothing",
		"skills":[], "toolsets":(tAll), "blocks":["sentinel", "agent"]})
	Do tRecipes.%Push({"id":"map-codes", "title":"Map unknown codes", "mode":"propose", "icon":"arrows-exchange", "kind":"kb",
		"description":"Agent proposes a code from your knowledge base, learned after approval",
		"skills":["AgenticProd.Skill.CodeMapping"], "toolsets":["AgenticProd.Tools.Base", "AgenticProd.Tools.Mapping"], "blocks":["sentinel", "agent", "human"]})
	Do tRecipes.%Push({"id":"resend", "title":"Resend when the target is back", "mode":"act", "icon":"refresh-alert", "kind":"po",
		"description":"For timeouts and outages: safe resend with a limit, the rest to a person",
		"skills":[], "toolsets":["AgenticProd.Tools.Base"], "blocks":["sentinel", "agent", "human"]})
	Do tRecipes.%Push({"id":"blank", "title":"Start blank", "mode":"observe", "icon":"square-plus", "kind":"",
		"description":"Empty agent, build it yourself from the blocks on the left",
		"skills":[], "toolsets":[], "blocks":["agent"]})
	Quit tRecipes
}

/// Draft for pNs/pName as {draft, savedBy, savedAt}; draft is null when none was saved.
ClassMethod Draft(pNs As %String, pName As %String) As %DynamicObject
{
	Set tOut = {"namespace":(pNs), "production":(pName), "draft":null}
	Set tRow = ##class(AgenticProd.Data.StudioDraft).Find(pNs, pName)
	If $IsObject(tRow) {
		Set tOut.draft = {}.%FromJSON(tRow.Json)
		Set tOut.savedBy = tRow.SavedBy, tOut.savedAt = tRow.SavedAt
	}
	Quit tOut
}

/// True when pNs is a namespace Productions lists, so the page cannot read arbitrary ones.
ClassMethod KnownNs(pNs As %String) As %Boolean
{
	Set tFound = 0
	If pNs '= "" {
		Set tIter = ..Productions().%GetIterator()
		While tIter.%GetNext(, .tRow) { Set:tRow.namespace=pNs tFound = 1 }
	}
	Quit tFound
}

}
