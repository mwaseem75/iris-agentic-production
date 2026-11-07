Include Ensemble

/// "Add to production" for a Workbench agent: adds the items that host it (and, for the failure
/// way, the Sentinel, check process and Workflow role) to a production in any namespace. Only adds;
/// an existing item, even of the same name, is never changed or restarted, and the request is
/// refused instead. Every added item is tracked in Data.PluginItem with Owner = the host item name,
/// so Remove takes out exactly those. The AI.* plug-in (Installer) is a separate install.
Class AgenticProd.Plugin.AddAgent
{

Parameter HOSTCLASS = "AgenticProd.Operation.Agent";

Parameter MODES = "observe,propose,act";

/// Ways in to the agent: when a message fails, from the customer's own process, from a routing rule.
Parameter WAYS = "failure,process,rule";

/// Item classes that are never offered in the watch list.
Parameter OWNCLASSES = "AgenticProd.Plugin.Sentinel,AgenticProd.Process.Triage,AgenticProd.Operation.Agent,EnsLib.Workflow.Operation";

/// Items of production pProduction in pNamespace with their 24 h error counts, most errors first,
/// plus the Workflow roles there. {"items":[{name,type,class,errors24h}],"roles":[]}.
ClassMethod Watchable(pNamespace As %String, pProduction As %String, pAgentClass As %String = "") As %DynamicObject
{
	Set tOut = {"items":[], "roles":[], "canFail":(''..ContractReady(pAgentClass))}
	Quit:'##class(AgenticProd.UI.Workbench).KnownNs(pNamespace) tOut
	Set tSince = ##class(AgenticProd.Plugin.Installer).Since()
	New $NAMESPACE
	Set $NAMESPACE = pNamespace
	Set tSC = ##class(AgenticProd.Plugin.Installer).OpenProduction(.pProduction, .tProd)
	Quit:$$$ISERR(tSC) tOut
	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i)
		Continue:((","_..#OWNCLASSES_",") [ (","_tItem.ClassName_","))
		Set tHealth = ##class(AgenticProd.UI.Workbench).ItemHealth(tItem.Name, tSince)
		Set tRow = {"name":(tItem.Name), "class":(tItem.ClassName), "type":(##class(AgenticProd.UI.Workbench).TypeOf(tItem.ClassName)), "errors24h":(tHealth.errors24h)}
		Do tOut.items.%Push(tRow)
	}
	// Errors first: those are the items worth watching
	Set tSorted = []
	Set tIter = tOut.items.%GetIterator()
	While tIter.%GetNext(, .tRow) { Set tKey(1000000 - tRow.errors24h, $INCREMENT(tN)) = tRow }
	Set tA = ""
	For {
		Set tA = $ORDER(tKey(tA))
		Quit:tA=""
		Set tB = ""
		For {
			Set tB = $ORDER(tKey(tA, tB), 1, tRow)
			Quit:tB=""
			Do tSorted.%Push(tRow)
		}
	}
	Set tOut.items = tSorted
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM EnsLib_Workflow.RoleDefinition ORDER BY Name")
		While tRS.%Next() { Do tOut.roles.%Push(tRS.Name) }
	} Catch {}
	Quit tOut
}

/// True when the agent class tells the model the decision-JSON answer format Triage parses (the
/// "## Output" section Wizard.OutputSection writes). Without it "When a message fails" cannot work.
ClassMethod ContractReady(pClass As %String) As %Boolean
{
	Quit:pClass="" 0
	Set tText = ##class(AgenticProd.UI.Workbench).SourceText(pClass)
	Quit (tText [ "## Output") && (tText [ """error_class""")
}

/// Check pSpec and list what would be added. pSpec: {agentClass, namespace, production, name,
/// way (WAYS), watch:[item names], mode (MODES), role, roleNew}. Returns {"ok", "errors":[],
/// "items":[{name,class,note}], "snippets":{objectscript,bpl,rule}}. Nothing is changed.
ClassMethod Plan(pSpec As %DynamicObject) As %DynamicObject
{
	Set tOut = {"ok":0, "errors":[], "items":[], "snippets":{}}
	Set tNs = pSpec.namespace, tProdName = pSpec.production, tName = pSpec.name, tWay = pSpec.way
	Set tClass = pSpec.agentClass
	If (tClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(tClass) || '$CLASSMETHOD(tClass, "%Extends", "%AI.Agent") {
		Do tOut.errors.%Push("Pick an agent class that exists in this namespace.")
	}
	If tName '? 1A.AN || ($LENGTH(tName) > 40) Do tOut.errors.%Push("The item name must start with a letter and use only letters and digits.")
	If '$LISTFIND($LISTFROMSTRING(..#WAYS), tWay) Do tOut.errors.%Push("Pick one of the three ways in.")
	If (tWay = "failure") && '..ContractReady(tClass) Do tOut.errors.%Push("This agent has no answer format for Triage. Build it with the Fix or Explain goal, or use one of the other two ways.")
	Set tMode = $SELECT(pSpec.mode = "": "propose", 1: pSpec.mode)
	If '$LISTFIND($LISTFROMSTRING(..#MODES), tMode) Do tOut.errors.%Push("Mode must be one of "_..#MODES_".")
	If '##class(AgenticProd.UI.Workbench).KnownNs(tNs) {
		Do tOut.errors.%Push("Pick a production.")
		Quit tOut
	}
	If tOut.errors.%Size() Quit tOut
	// The host item always; the failure way adds the watch, check and Workflow items
	Do tOut.items.%Push({"name":(tName), "class":(..#HOSTCLASS), "note":("hosts "_tClass_" · "_..BudgetNote(tClass))})
	Set tRole = ""
	If tWay = "failure" {
		Set tWatch = pSpec.watch
		If '$IsObject(tWatch) || 'tWatch.%Size() Do tOut.errors.%Push("Tick at least one item to watch.")
		Set tRole = $SELECT(pSpec.role '= "": pSpec.role, 1: pSpec.roleNew)
		If tRole '? 1A.AN Do tOut.errors.%Push("Give the approver role a name (letters and digits).")
		Do tOut.items.%Push({"name":(tName_"Watch"), "class":"AgenticProd.Plugin.Sentinel", "note":("custom adapter · watches "_..Csv(tWatch))})
		Do tOut.items.%Push({"name":(tName_"Check"), "class":"AgenticProd.Process.Triage", "note":("checks every answer before anything changes · "_tMode)})
	}
	Set tOut.snippets = ..Snippets(tName)
	If tOut.errors.%Size() Quit tOut
	// The agent's package must be visible in the target namespace: map it when it is not
	Set tHome = $NAMESPACE, tPkg = $PIECE(tClass, ".", 1), tMapped = ..MappingExists(tNs, tPkg)
	If (tNs '= tHome) && 'tMapped {
		Do tOut.items.%Push({"name":("Package mapping "_tPkg_" -> "_tNs), "class":"Config.MapPackages", "kind":"package", "note":("so "_tNs_" can see "_tPkg_".* (agent, tools, policy); added to the namespace config")})
	}
	New $NAMESPACE
	Set $NAMESPACE = tNs
	Set tSC = ##class(AgenticProd.Plugin.Installer).OpenProduction(.tProdName, .tProd)
	If $$$ISERR(tSC) {
		Do tOut.errors.%Push($SYSTEM.Status.GetErrorText(tSC))
		Quit tOut
	}
	If (tMapped || (tNs = tHome)) && '##class(%Dictionary.CompiledClass).%ExistsId(tClass) Do tOut.errors.%Push(tClass_" is not visible in namespace "_tNs_" although "_tPkg_" is mapped there.")
	If '##class(%Dictionary.CompiledClass).%ExistsId(..#HOSTCLASS) Do tOut.errors.%Push("The AgenticProd classes are not mapped into namespace "_tNs_"; run Setup.LegacyMappings first.")
	// Role item: an existing Workflow operation of that name is reused, anything else with it is a clash
	If tRole '= "" {
		Set tExisting = tProd.FindItemByConfigName(tRole)
		If $IsObject(tExisting) && (tExisting.ClassName '= "EnsLib.Workflow.Operation") {
			Do tOut.errors.%Push("Item "_tRole_" exists and is not a Workflow operation.")
		} ElseIf '$IsObject(tExisting) {
			Do tOut.items.%Push({"name":(tRole), "class":"EnsLib.Workflow.Operation", "note":("Workflow · role "_tRole)})
		}
	}
	Set tIter = tOut.items.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		If (tRow.name = tRole) || (tRow.kind = "package") Continue
		If $IsObject(tProd.FindItemByConfigName(tRow.name)) Do tOut.errors.%Push(tNs_" "_tProdName_" already has an item named "_tRow.name_". Nothing was changed; pick another name.")
	}
	Set tOut.ok = 'tOut.errors.%Size()
	Quit tOut
}

/// Add the items Plan lists and apply them when the production is running. Returns
/// {"ok","errors":[],"added":[names]}. A failed plan changes nothing.
ClassMethod Apply(pSpec As %DynamicObject) As %DynamicObject
{
	Set tPlan = ..Plan(pSpec)
	Set tOut = {"ok":0, "errors":(tPlan.errors), "added":[]}
	Quit:'tPlan.ok tOut
	Set tNs = pSpec.namespace, tProdName = pSpec.production, tName = pSpec.name, tClass = pSpec.agentClass
	Set tWay = pSpec.way, tMode = $SELECT(pSpec.mode = "": "propose", 1: pSpec.mode)
	Set tCreated = 0, tPkg = $PIECE(tClass, ".", 1), tHome = $NAMESPACE
	Try {
		// Settings come from the home production's TriageAgent item; read before switching namespace
		Set tOver = ""
		$$$ThrowOnError(##class(AgenticProd.Plugin.Installer).AgentItemSettings(.tOver, "LabCodeMap", .tList))
		Set tList("AgentClass") = $LISTBUILD("Host", tClass)
		Set tModel = $PARAMETER(tClass, "MODEL"), tCfg = $PARAMETER(tClass, "PROVIDERCONFIG")
		Set:tModel'="" tList("Model") = $LISTBUILD("Host", tModel)
		Set:tCfg'="" tList("ProviderConfig") = $LISTBUILD("Host", tCfg)
		Set tRole = $SELECT(pSpec.role '= "": pSpec.role, 1: pSpec.roleNew)
		// Mapping first: the production items name classes of this package
		If (tNs '= tHome) && '..MappingExists(tNs, tPkg) {
			$$$ThrowOnError(..AddMapping(tNs, tPkg))
			Set tCreated = 1
		}
		New $NAMESPACE
		Set $NAMESPACE = tNs
		$$$ThrowOnError(##class(AgenticProd.Plugin.Installer).OpenProduction(.tProdName, .tProd))
		Set tIter = tPlan.items.%GetIterator()
		While tIter.%GetNext(, .tRow) {
			Continue:(tRow.kind = "package")
			Set tItem = ##class(Ens.Config.Item).%New()
			Set tItem.Name = tRow.name, tItem.ClassName = tRow.class, tItem.PoolSize = 1, tItem.Enabled = 1
			Set tItem.Category = "AI Hub agent: "_tName, tItem.Comment = "Added by AgenticProd.Plugin.AddAgent; Remove takes it out"
			If tRow.name = tName {
				Do ##class(AgenticProd.Plugin.Installer).SetAgentItem(tItem, .tList)
			} ElseIf tRow.class = "AgenticProd.Plugin.Sentinel" {
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "TargetConfigName", tName_"Check")
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "WatchItems", ..Csv(pSpec.watch), "Adapter")
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "OwnPrefix", tName, "Adapter")
			} ElseIf tRow.class = "AgenticProd.Process.Triage" {
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "AgentTarget", tName)
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "ApprovalTarget", tRole)
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "ActionMode", tMode)
			} Else {
				Do ##class(AgenticProd.Plugin.Installer).AddSetting(tItem, "AutoCreateRole", 1)
			}
			Do tProd.Items.Insert(tItem)
			Kill $$$EnsStaticAppData(tRow.name)
		}
		If tRole '= "" && (tWay = "failure") $$$ThrowOnError(##class(AgenticProd.Plugin.Installer).ReviewRole(tRole))
		$$$ThrowOnError(##class(AgenticProd.Plugin.Installer).SaveAndApply(tProd))
		// One mapping row per install that relies on it; the first one created it
		If tNs '= tHome {
			$$$ThrowOnError(..Track(tNs, tProdName, "Package mapping "_tPkg_" -> "_tNs_" for "_tName, "Config.MapPackages", $SELECT(tCreated: "created", 1: "used"), tName, tPkg))
			Do:tCreated tOut.added.%Push("Package mapping "_tPkg_" -> "_tNs)
		}
		Set tIter = tPlan.items.%GetIterator()
		While tIter.%GetNext(, .tRow) {
			Continue:(tRow.kind = "package")
			$$$ThrowOnError(..Track(tNs, tProdName, tRow.name, tRow.class, $SELECT(tWay = "failure": tMode, 1: tWay), tName, $SELECT(tRow.name = tName: tClass, 1: "")))
			Do tOut.added.%Push(tRow.name)
		}
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", tNs_" "_tProdName, "add agent", "", tName_" ("_tClass_", "_tWay_")"))
		Set tOut.ok = 1
	} Catch ex {
		Do tOut.errors.%Push($SYSTEM.Status.GetErrorText(ex.AsStatus()))
		// Nothing else uses a mapping this call just made
		If tCreated Do ..RemoveMapping(tNs, tPkg)
	}
	Quit tOut
}

/// Apply from a JSON spec in a background job (Job ..ApplyJob(key, json)): a production update can
/// outlast an HTTP call. The result is left in ^IRIS.Temp.AgenticProdAdd(pKey).
ClassMethod ApplyJob(pKey As %String, pJson As %String) [ Internal ]
{
	Set ^IRIS.Temp.AgenticProdAdd(pKey) = "running"
	Set ^IRIS.Temp.AgenticProdAdd(pKey) = ..Apply({}.%FromJSON(pJson)).%ToJSON()
}

/// Take out the items of install pOwner in pNamespace/pProduction, exactly the tracked ones, then
/// drop the rows. Returns {"ok","errors":[],"removed":[names]}. The Workflow role and its tasks
/// stay: they are the record of what people decided.
ClassMethod Remove(pNamespace As %String, pProduction As %String, pOwner As %String) As %DynamicObject
{
	Set tOut = {"ok":0, "errors":[], "removed":[]}
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ItemName FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ? AND Owner = ?", pNamespace, pProduction, pOwner)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While tRS.%Next() { Set tRows(tRS.ID) = tRS.ItemName }
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT AgentClass, Mode FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ? AND Owner = ? AND ClassName = 'Config.MapPackages'", pNamespace, pProduction, pOwner)
		Set tMapPkg = "", tMapCreated = 0
		If tRS.%Next() Set tMapPkg = tRS.AgentClass, tMapCreated = (tRS.Mode = "created")
		If '$DATA(tRows) {
			Do tOut.errors.%Push("No install named "_pOwner_" in "_pNamespace_" "_pProduction_".")
			Quit
		}
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(##class(AgenticProd.Plugin.Installer).OpenProduction(.pProduction, .tProd))
		Set tId = ""
		For {
			Set tId = $ORDER(tRows(tId), 1, tItemName)
			Quit:tId=""
			Set tItem = tProd.FindItemByConfigName(tItemName)
			If $IsObject(tItem) {
				Do tProd.RemoveItem(tItem)
				Do tOut.removed.%Push(tItemName)
			}
		}
		$$$ThrowOnError(##class(AgenticProd.Plugin.Installer).SaveAndApply(tProd))
		// Once the jobs are stopped: queued requests would otherwise run on a later install
		Set tId = ""
		For {
			Set tId = $ORDER(tRows(tId), 1, tItemName)
			Quit:tId=""
			Kill $$$EnsStaticAppData(tItemName)
			If $DATA(^Ens.Queue(tItemName)) $$$ThrowOnError(##class(Ens.Queue).AbortQueue(tItemName))
		}
		Set tId = ""
		For {
			Set tId = $ORDER(tRows(tId))
			Quit:tId=""
			$$$ThrowOnError(##class(AgenticProd.Data.PluginItem).%DeleteId(tId))
		}
		If tMapPkg '= "" {
			// Another install in this namespace may still need the package: it takes over the creator role
			Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND ClassName = 'Config.MapPackages' AND AgentClass = ?", pNamespace, tMapPkg)
			If tRS.%Next() {
				If tMapCreated {
					Set tOther = ##class(AgenticProd.Data.PluginItem).%OpenId(tRS.ID)
					Set tOther.Mode = "created"
					$$$ThrowOnError(tOther.%Save())
				}
			} ElseIf tMapCreated {
				$$$ThrowOnError(..RemoveMapping(pNamespace, tMapPkg))
				Do tOut.removed.%Push("Package mapping "_tMapPkg_" -> "_pNamespace)
			}
		}
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", pNamespace_" "_pProduction, "add agent", pOwner, "removed"))
		Set tOut.ok = 1
	} Catch ex {
		Do tOut.errors.%Push($SYSTEM.Status.GetErrorText(ex.AsStatus()))
	}
	Quit tOut
}

/// Installs made here: [{namespace, production, owner, agentClass, way, mode (observe|propose|act, failure way only), items:[names], addedAt}].
/// pAgentClass limits it to one agent class; pNamespace/pProduction to one production.
ClassMethod Installs(pAgentClass As %String = "", pNamespace As %String = "", pProduction As %String = "") As %DynamicArray
{
	Set tOut = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, Production, Owner, ItemName, AgentClass, Mode, AddedAt FROM AgenticProd_Data.PluginItem WHERE Owner IS NOT NULL AND Owner <> '' ORDER BY ID")
	While tRS.%Next() {
		Continue:((pNamespace '= "") && ((tRS.Namespace '= pNamespace) || (tRS.Production '= pProduction)))
		Set tKey = tRS.Namespace_"|"_tRS.Production_"|"_tRS.Owner
		If '$DATA(tByKey(tKey)) {
			Set tByKey(tKey) = {"namespace":(tRS.Namespace), "production":(tRS.Production), "owner":(tRS.Owner), "agentClass":"", "way":"", "mode":"", "items":[], "addedAt":(tRS.AddedAt)}
			Do tOut.%Push(tByKey(tKey))
		}
		Do tByKey(tKey).items.%Push(tRS.ItemName)
		If tRS.ItemName = tRS.Owner {
			Set tIsMode = $LISTFIND($LISTFROMSTRING(..#MODES), tRS.Mode)
			// Mode is stored only for the failure way; the other ways keep the way in that column
			Set tByKey(tKey).agentClass = tRS.AgentClass, tByKey(tKey).way = $SELECT(tIsMode: "failure", 1: tRS.Mode), tByKey(tKey).mode = $SELECT(tIsMode: tRS.Mode, 1: "")
		}
	}
	If pAgentClass '= "" {
		Set tAll = tOut, tOut = []
		Set tIter = tAll.%GetIterator()
		While tIter.%GetNext(, .tRow) { Do:(tRow.agentClass = pAgentClass) tOut.%Push(tRow) }
	}
	Quit tOut
}

/// Endpoint entry: pAction plan, apply or remove. Plan and apply need an administrator.
ClassMethod Handle(pAction As %String, pBody As %DynamicObject, pAdmin As %Boolean) As %DynamicObject
{
	If 'pAdmin Quit {"status":403, "error":"Adding an agent to a production is for administrators."}
	Set tRes = ""
	If pAction = "plan" { Set tRes = ..Plan(pBody) }
	ElseIf pAction = "apply" { Set tRes = ..Apply(pBody) }
	ElseIf pAction = "remove" { Set tRes = ..Remove(pBody.namespace, pBody.production, pBody.owner) }
	If '$IsObject(tRes) Quit {"status":400, "error":"unknown action"}
	Do tRes.%Set("status", 200, "number")
	Quit tRes
}

/// ObjectScript, BPL and routing-rule text for calling item pName.
ClassMethod Snippets(pName As %String) As %DynamicObject
{
	Set tNL = $CHAR(10)
	Set tOs = "// inside your business process"_tNL
		_"Set req = ##class(AgenticProd.Msg.AgentRequest).%New()"_tNL
		_"Set req.HeaderId = pRequest.%Id()  // the message the agent should look at"_tNL
		_"Set req.Question = ""Why did this order fail? Propose one decision."""_tNL
		_"Set tSC = ..SendRequestSync("""_pName_""", req, .resp)"_tNL
		_"If $$$ISOK(tSC) {"_tNL
		_"    // resp.Decision (RESEND, ESCALATE, ...), resp.Confidence, resp.Reason, resp.Text"_tNL
		_"}"
	Set tBpl = "<call name=""Ask agent"" target="""_pName_""" async=""0"">"_tNL
		_"  <request type=""AgenticProd.Msg.AgentRequest"">"_tNL
		_"    <assign property=""callrequest.Question"" value=""Why did this order fail?"" action=""set""/>"_tNL
		_"  </request>"_tNL
		_"  <response type=""AgenticProd.Msg.AgentResponse""/>"_tNL
		_"</call>"
	Set tRule = "<send transform=""MyApp.ToAgentRequest"" target="""_pName_"""/>"
	Quit {"objectscript":(tOs), "bpl":(tBpl), "rule":(tRule)}
}

/// True when namespace pNs maps package pPkg (read in %SYS, where the namespace config lives).
ClassMethod MappingExists(pNs As %String, pPkg As %String) As %Boolean [ Internal ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit ''##class(Config.MapPackages).Exists(pNs, pPkg)
}

/// Map pPkg into pNs from the database the current namespace keeps its classes in, the way
/// Setup.LegacyMappings maps AgenticProd.
ClassMethod AddMapping(pNs As %String, pPkg As %String) As %Status [ Internal ]
{
	Set tHome = $NAMESPACE, tSC = $$$OK
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Try {
		$$$ThrowOnError(##class(Config.Namespaces).Get(tHome, .tNSProps))
		Set tProps("Database") = tNSProps("Routines")
		$$$ThrowOnError(##class(Config.MapPackages).Create(pNs, pPkg, .tProps))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod RemoveMapping(pNs As %String, pPkg As %String) As %Status [ Internal ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit:'##class(Config.MapPackages).Exists(pNs, pPkg) $$$OK
	Quit ##class(Config.MapPackages).Delete(pNs, pPkg)
}

ClassMethod BudgetNote(pClass As %String) As %String [ Internal ]
{
	Set tBudget = +$PARAMETER(pClass, "DAILYBUDGET")
	Quit $SELECT(tBudget: "$"_$FNUMBER(tBudget, "", 2)_"/day", 1: "no daily budget")
}

ClassMethod Csv(pList As %DynamicArray) As %String [ Internal ]
{
	Set tOut = "", tIter = pList.%GetIterator()
	While tIter.%GetNext(, .tVal) { Set tOut = tOut_$SELECT(tOut '= "": ",", 1: "")_tVal }
	Quit tOut
}

ClassMethod Track(pNamespace As %String, pProduction As %String, pItem As %String, pClass As %String, pMode As %String, pOwner As %String, pAgentClass As %String) As %Status [ Internal ]
{
	Set tRow = ##class(AgenticProd.Data.PluginItem).%New()
	Set tRow.Namespace = pNamespace, tRow.Production = pProduction, tRow.ItemName = pItem
	Set tRow.ClassName = pClass, tRow.Mode = pMode, tRow.Owner = pOwner, tRow.AgentClass = pAgentClass
	Quit tRow.%Save()
}

}
