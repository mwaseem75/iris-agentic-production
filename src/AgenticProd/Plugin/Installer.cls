Include Ensemble

/// Adds the AI plug-in (Sentinel, Triage, agent, review inbox) to an existing production in
/// another namespace, switches its mode and takes it out again. Only touches the production
/// through Ens.Config.Production, and every item it adds is tracked in Data.PluginItem, so Disable
/// removes exactly those. The namespace needs the AgenticProd mappings and grants first
/// (Setup.LegacyMappings, AgentSecurity). Changes are logged in Data.SettingsAudit.
Class AgenticProd.Plugin.Installer
{

/// Config name prefix of every plug-in item; the Sentinel skips messages to and from them.
Parameter PREFIX = "AI.";

/// Config name suffix = class of each item Enable adds, in production order. Review is the
/// Workflow operation: its config name is also the role its tasks go to.
Parameter ITEMS = "Sentinel=AgenticProd.Plugin.Sentinel,Triage=AgenticProd.Process.Triage,Agent=AgenticProd.Operation.Agent,Review=EnsLib.Workflow.Operation";

/// Agent item in this namespace's production whose settings (provider, model, budgets) the
/// plug-in agent starts with.
Parameter AGENTSOURCE = "TriageAgent";

/// Agent settings an install may set itself. Provider, model, limits and budget always come from
/// AGENTSOURCE: an override of MaxIterations once left the LEGACY agent at 3 tool rounds.
Parameter AGENTOVERRIDES = "KillSwitch,CodeTable";

Parameter UPDATETIMEOUT = 60;

/// observe: logs what it would do; propose: every decision to the review inbox; act: Triage's
/// action matrix (whitelisted fixes, transient RESEND, REJECT, the rest to a person).
Parameter MODES = "observe,propose,act";

/// Add the plug-in items to pProduction in pNamespace (default: the production there now) and
/// apply them if it is running. pAdded = item names added. Running it again adds only what is
/// missing; an item of the same name that the plug-in did not add is an error, nothing is changed.
/// pAgentSettings(name) = value overrides one of AGENTOVERRIDES (e.g. KillSwitch=1 installs it
/// with the AI off); anything else is an error. pCodeTable / pCodeFormat: the production's code table and its value
/// format (Triage.CodeTableFormat).
ClassMethod Enable(pNamespace As %String, pProduction As %String = "", pMode As %String = "observe", Output pAdded As %String, ByRef pAgentSettings, pCodeTable As %String = "LabCodeMap", pCodeFormat As %String = "loinc^display") As %Status
{
	Set pAdded = ""
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CheckMode(pMode))
		If pNamespace = $NAMESPACE $$$ThrowStatus($$$ERROR($$$GeneralError, "the plug-in goes into another namespace's production, not "_$NAMESPACE))
		$$$ThrowOnError(..AgentItemSettings(.pAgentSettings, pCodeTable, .tAgentSettings))
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		For i = 1:1:$LENGTH(..#ITEMS, ",") {
			Set tPair = $PIECE(..#ITEMS, ",", i), tSuffix = $PIECE(tPair, "="), tName = ..#PREFIX_tSuffix, tClass = $PIECE(tPair, "=", 2)
			If $IsObject(tProd.FindItemByConfigName(tName)) {
				// Someone else's item with our name: tracking it would let Disable remove it
				If '##class(AgenticProd.Data.PluginItem).ItemIdxExists(pNamespace, pProduction, tName) $$$ThrowStatus($$$ERROR($$$GeneralError, pProduction_" already has an item "_tName_" the plug-in did not add"))
			} Else {
				Set tItem = ##class(Ens.Config.Item).%New()
				Set tItem.Name = tName, tItem.ClassName = tClass, tItem.PoolSize = 1, tItem.Enabled = 1
				Set tItem.Category = "AgenticProd plug-in", tItem.Comment = "Added by AgenticProd.Plugin.Installer; Disable removes it"
				If tSuffix = "Sentinel" {
					Do ..AddSetting(tItem, "TargetConfigName", ..#PREFIX_"Triage")
				} ElseIf tSuffix = "Triage" {
					Do ..AddSetting(tItem, "AgentTarget", ..#PREFIX_"Agent")
					Do ..AddSetting(tItem, "ApprovalTarget", ..#PREFIX_"Review")
					Do ..AddSetting(tItem, "ActionMode", pMode)
					Do ..AddSetting(tItem, "CodeTable", pCodeTable)
					Do ..AddSetting(tItem, "CodeTableFormat", pCodeFormat)
				} ElseIf tSuffix = "Review" {
					Do ..AddSetting(tItem, "AutoCreateRole", 1)
				} Else {
					Do ..SetAgentItem(tItem, .tAgentSettings)
				}
				Do tProd.Items.Insert(tItem)
				// Marks left by an earlier install would make a new Sentinel rescan from there
				Kill $$$EnsStaticAppData(tName)
				Set pAdded = pAdded_$SELECT(pAdded '= "": ",", 1: "")_tName
			}
			$$$ThrowOnError(..Track(pNamespace, pProduction, tName, tClass, pMode))
		}
		Quit:pAdded=""
		$$$ThrowOnError(..ReviewRole(..#PREFIX_"Review"))
		$$$ThrowOnError(..SaveAndApply(tProd))
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", pNamespace_" "_pProduction, "plug-in", "", "enabled ("_pMode_", "_pCodeTable_")"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Remove every tracked plug-in item from pProduction in pNamespace, apply that if it is
/// running, and drop the tracking rows. pRemoved = item names removed. Items the installer did
/// not add are never touched, whatever their name. The review role and its tasks stay: they are
/// the record of what people decided.
ClassMethod Disable(pNamespace As %String, pProduction As %String = "", Output pRemoved As %String) As %Status
{
	Set pRemoved = ""
	Set tSC = $$$OK
	Try {
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ItemName FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ? AND (Owner IS NULL OR Owner = '')", pNamespace, pProduction)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While tRS.%Next() {
			Set tItem = tProd.FindItemByConfigName(tRS.ItemName)
			If $IsObject(tItem) {
				Do tProd.RemoveItem(tItem)
				Set pRemoved = pRemoved_$SELECT(pRemoved '= "": ",", 1: "")_tRS.ItemName
			}
			Set tIds($INCREMENT(tIds)) = tRS.ID
		}
		// Also when the items are already gone: an earlier update may have left their jobs running
		If $GET(tIds) $$$ThrowOnError(..SaveAndApply(tProd))
		// Only once the jobs are stopped: requests still queued to a removed item would run (and
		// call the LLM) on the next Enable, and the Sentinel's marks go with it
		For i = 1:1:$GET(tIds) {
			Set tName = ##class(AgenticProd.Data.PluginItem).%OpenId(tIds(i)).ItemName
			Kill $$$EnsStaticAppData(tName)
			// A service (the Sentinel) has no queue
			If $DATA(^Ens.Queue(tName)) $$$ThrowOnError(##class(Ens.Queue).AbortQueue(tName))
		}
		// Rows go after the production change, so a failed save leaves them for another try
		For i = 1:1:$GET(tIds) $$$ThrowOnError(##class(AgenticProd.Data.PluginItem).%DeleteId(tIds(i)))
		If pRemoved '= "" $$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", pNamespace_" "_pProduction, "plug-in", "enabled", "disabled"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Switch the plug-in of pProduction in pNamespace to pMode (MODES): AI.Triage's ActionMode,
/// the tracking rows and the change log. pNote: set when the value was saved but the item did
/// not restart in time.
ClassMethod SetMode(pNamespace As %String, pProduction As %String = "", pMode As %String, Output pNote As %String) As %Status
{
	Set pNote = ""
	Set tSC = $$$OK
	Try {
		$$$ThrowOnError(..CheckMode(pMode))
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		Set tTriage = ..#PREFIX_"Triage"
		If '##class(AgenticProd.Data.PluginItem).ItemIdxExists(pNamespace, pProduction, tTriage) $$$ThrowStatus($$$ERROR($$$GeneralError, "the plug-in is not enabled on "_pNamespace_" "_pProduction))
		Set tOld = ..ItemSetting(tProd, tTriage, "ActionMode")
		Quit:tOld=pMode
		Set tSettings(tTriage, "Host", "ActionMode") = pMode
		$$$ThrowOnError(..Apply(pProduction, .tSettings, tTriage, "ActionMode", .pNote))
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "UPDATE AgenticProd_Data.PluginItem SET Mode = ? WHERE Namespace = ? AND Production = ? AND (Owner IS NULL OR Owner = '')", pMode, pNamespace, pProduction)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", pNamespace_" "_pProduction, "mode", tOld, pMode))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Set agent setting pName to pValue on the AI.Agent item of every plug-in install (the kill
/// switch reaches them all this way). Each change is logged. pNote lists items that saved the
/// value but did not restart in time; a value that was not saved is an error.
ClassMethod ApplyAgentSetting(pName As %String, pValue As %String, Output pNote As %String) As %Status
{
	Set pNote = ""
	Set tSC = $$$OK
	Try {
		Set tAgent = ..#PREFIX_"Agent"
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, Production FROM AgenticProd_Data.PluginItem WHERE ItemName = ?", tAgent)
		If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
		While tRS.%Next() {
			Set tTargets(tRS.Namespace, tRS.Production) = ""
		}
		Set tNS = ""
		For {
			Set tNS = $ORDER(tTargets(tNS))
			Quit:tNS=""
			Set tProdName = ""
			For {
				Set tProdName = $ORDER(tTargets(tNS, tProdName))
				Quit:tProdName=""
				$$$ThrowOnError(..ApplyIn(tNS, tProdName, tAgent, pName, pValue, .tItemNote))
				Set:tItemNote'="" pNote = pNote_$SELECT(pNote '= "": "; ", 1: "")_tNS_": "_tItemNote
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod ApplyIn(pNamespace As %String, pProduction As %String, pItem As %String, pName As %String, pValue As %String, Output pNote As %String) As %Status [ Internal ]
{
	Set pNote = ""
	New $NAMESPACE
	Set $NAMESPACE = pNamespace
	Set tSC = ..OpenProduction(pProduction, .tProd)
	Quit:$$$ISERR(tSC) tSC
	Set tOld = ..ItemSetting(tProd, pItem, pName)
	Quit:tOld=pValue $$$OK
	Set tSettings(pItem, "Host", pName) = pValue
	Set tSC = ..Apply(pProduction, .tSettings, pItem, pName, .pNote)
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(AgenticProd.Data.SettingsAudit).Log("budgets", pNamespace_" "_pItem, pName, tOld, pValue)
}

/// Every production with the plug-in, the home production, and productions in namespaces that
/// have the AgenticProd mappings but no plug-in yet (enabled false), each with health
/// (Health) and the last 24 h of decisions and agent cost from the shared tables.
ClassMethod Productions() As %DynamicArray
{
	Set tOut = []
	Set tHome = $NAMESPACE, tHomeProd = ##class(AgenticProd.Production).%ClassName(1)
	Set tSince = ..Since(), tSeen(tHome) = ""
	Set tRow = {"namespace":(tHome), "production":(tHomeProd), "mode":(..HomeMode()), "items":[], "native":true, "enabled":true}
	Do tOut.%Push(tRow)
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, Production, Mode, ItemName, AddedAt, AddedBy FROM AgenticProd_Data.PluginItem WHERE (Owner IS NULL OR Owner = '') ORDER BY Namespace, Production, ID")
	While tRS.%Next() {
		Set tKey = tRS.Namespace_"|"_tRS.Production
		If '$DATA(tByKey(tKey)) {
			Set tByKey(tKey) = {"namespace":(tRS.Namespace), "production":(tRS.Production), "mode":(tRS.Mode), "items":[], "native":false, "enabled":true, "addedAt":(tRS.AddedAt), "addedBy":(tRS.AddedBy)}
			Do tOut.%Push(tByKey(tKey))
			Set tSeen(tRS.Namespace) = ""
		}
		Do tByKey(tKey).items.%Push(tRS.ItemName)
	}
	// Not yet enabled: namespaces where the plug-in classes resolve (mapped) but nothing is installed
	Do ##class(%SYS.Namespace).ListAll(.tList)
	Set tNS = ""
	For {
		Set tNS = $ORDER(tList(tNS))
		Quit:tNS=""
		Continue:$DATA(tSeen(tNS))||($EXTRACT(tNS)="%")||(tNS["^")
		Set tProdName = ..CandidateProduction(tNS)
		Continue:tProdName=""
		Do tOut.%Push({"namespace":(tNS), "production":(tProdName), "mode":"", "items":[], "native":false, "enabled":false})
	}
	Set tIter = tOut.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Do tRow.%Set("active", ..Active(tRow.namespace, tRow.enabled), "boolean")
		Set tRow.health = ..Health(tRow.namespace, tRow.production, tSince)
		Set tStats = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS Decisions FROM AgenticProd_Data.DecisionLog WHERE Namespace = ? AND CreatedAt >= ? AND EvalRunId IS NULL", tRow.namespace, tSince).%Get(0)
		Set tCost = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS Runs, SUM(CostUsd) AS Cost FROM AgenticProd_Data.Usage WHERE Namespace = ? AND CreatedAt >= ? AND (Replay = 0 OR Replay IS NULL) AND EvalRunId IS NULL", tRow.namespace, tSince).%Get(0)
		Set tRow.decisions24h = +tStats.Decisions, tRow.agentRuns24h = +tCost.Runs, tRow.cost24h = +tCost.Cost
		Do tRow.%Set("native", ''tRow.native, "boolean"), tRow.%Set("enabled", ''tRow.enabled, "boolean")
	}
	Quit tOut
}

/// True when the Messages filter should list the namespace: the plug-in is enabled there, an agent
/// was added through Add to production, or it has decisions of its own. Enabled alone missed the
/// productions that only got an Add AI Hub agent install.
ClassMethod Active(pNamespace As %String, pEnabled As %Boolean = 0) As %Boolean
{
	Quit:pEnabled 1
	Quit:##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 ID FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Owner IS NOT NULL AND Owner <> ''", pNamespace).%Size() 1
	Quit ''##class(AgenticProd.UI.REST).Rows("SELECT TOP 1 ID FROM AgenticProd_Data.DecisionLog WHERE Namespace = ?", pNamespace).%Size()
}

/// Running state, failed and suspended headers, event-log errors (last 24 h from pSince) and
/// messages waiting in queues, read in pNamespace.
ClassMethod Health(pNamespace As %String, pProduction As %String, pSince As %String) As %DynamicObject
{
	Set tOut = {"state":"unknown"}
	Try {
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
		Set tOut.state = $SELECT(tName '= pProduction: "not current", tState = $$$eProductionStateRunning: "running", tState = $$$eProductionStateStopped: "stopped", 1: "troubled")
		Set tOut.failed24h = +##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE IsError = 1 AND TimeCreated >= ?", pSince).%Get(0).N
		Set tOut.suspended = +##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE %EXTERNAL(Status) = 'Suspended'").%Get(0).N
		Set tOut.errors24h = +##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM Ens_Util.Log WHERE %EXTERNAL(Type) = 'Error' AND TimeLogged >= ?", pSince).%Get(0).N
		Set tQueued = 0, tQueue = ""
		For {
			Set tQueue = $ORDER(^Ens.Queue(tQueue))
			Quit:tQueue=""
			Set tQueued = tQueued + $GET(^Ens.Queue(tQueue, 0, "count"))
		}
		Set tOut.queued = tQueued
	} Catch ex {
		Set tOut.error = $SYSTEM.Status.GetErrorText(ex.AsStatus())
	}
	Quit tOut
}

/// UTC timestamp 24 hours ago.
ClassMethod Since() As %String [ Internal ]
{
	Set tNow = $ZTIMESTAMP
	Quit $ZDATETIME((tNow - 1)_","_$PIECE(tNow, ",", 2), 3)
}

/// Current production of pNamespace when the plug-in classes resolve there, else "".
ClassMethod CandidateProduction(pNamespace As %String) As %String [ Internal ]
{
	Set tName = ""
	Try {
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		Quit:'##class(%Dictionary.CompiledClass).%ExistsId($CLASSNAME())
		Quit:'##class(%Dictionary.CompiledClass).%ExistsId("Ens.Director")
		Do ##class(Ens.Director).GetProductionStatus(.tName)
	} Catch ex {
		Set tName = ""
	}
	Quit tName
}

/// ActionMode of the home production's Triage item.
ClassMethod HomeMode() As %String [ Internal ]
{
	Set tMode = ##class(Ens.Director).GetHostSettingValue("Triage", "ActionMode", .tSC)
	Quit $SELECT($$$ISOK(tSC) && (tMode '= ""): tMode, 1: "act")
}

/// Setting pName of item pItem in pProd, else the item class's default.
ClassMethod ItemSetting(pProd As Ens.Config.Production, pItem As %String, pName As %String) As %String [ Internal ]
{
	Set tItem = pProd.FindItemByConfigName(pItem)
	Quit:'$IsObject(tItem) ""
	Quit:tItem.GetSetting(pName, .tValue) tValue
	Set tProp = ##class(%Dictionary.CompiledProperty).%OpenId(tItem.ClassName_"||"_pName)
	Quit $SELECT($IsObject(tProp): $ZSTRIP(tProp.InitialExpression, "<>", """"), 1: "")
}

/// Workflow role pRole (the AI.Review item's tasks) with the demo reviewer in it, in this
/// namespace. Workflow roles and users are per namespace.
ClassMethod ReviewRole(pRole As %String) As %Status [ Internal ]
{
	Set tSC = $$$OK
	Try {
		Set tUser = ##class(AgenticProd.Setup).#REVIEWUSER
		If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(pRole) $$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).CreateRole(pRole))
		If '##class(EnsLib.Workflow.UserDefinition).%ExistsId(tUser) $$$ThrowOnError(##class(EnsLib.Workflow.UserDefinition).CreateUser(tUser, "Demo reviewer"))
		If '##class(EnsLib.Workflow.RoleMembership).%ExistsId(pRole_"||"_tUser) $$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(pRole, tUser))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod CheckMode(pMode As %String) As %Status [ Internal ]
{
	Quit:$LISTFIND($LISTFROMSTRING(..#MODES), pMode) $$$OK
	Quit $$$ERROR($$$GeneralError, "mode must be one of "_..#MODES_", not '"_pMode_"'")
}

/// Reset the plug-in agent item in pNamespace to AGENTSOURCE's settings, keeping its own
/// KillSwitch and CodeTable, and apply that if the production runs. pChanged = names whose value
/// changed or that were dropped; nothing is saved when it already matches.
ClassMethod SyncAgent(pNamespace As %String, pProduction As %String = "", Output pChanged As %String) As %Status
{
	Set pChanged = ""
	Set tSC = $$$OK
	Try {
		If pNamespace = $NAMESPACE $$$ThrowStatus($$$ERROR($$$GeneralError, "the plug-in agent is in another namespace, not "_$NAMESPACE))
		Do ..AgentSettings(.tSource)
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		Set tItem = tProd.FindItemByConfigName(..#PREFIX_"Agent")
		If '$IsObject(tItem) $$$ThrowStatus($$$ERROR($$$GeneralError, pProduction_" has no plug-in agent"))
		Set tOverrides = $LISTFROMSTRING(..#AGENTOVERRIDES), tPtr = 0
		While $LISTNEXT(tOverrides, tPtr, tName) {
			Set:tItem.GetSetting(tName, .tValue) tKeep(tName) = tValue
		}
		$$$ThrowOnError(..MergeAgentSettings(.tSource, .tKeep, $GET(tKeep("CodeTable"), "LabCodeMap"), .tWanted))
		For i = 1:1:tItem.Settings.Count() {
			Set tSetting = tItem.Settings.GetAt(i), tName = tSetting.Name
			Set tHave(tName) = tSetting.Value
			If '$DATA(tWanted(tName)) || ($LIST(tWanted(tName), 2) '= tSetting.Value) Set pChanged = pChanged_$SELECT(pChanged '= "": ",", 1: "")_tName
		}
		Set tName = ""
		For {
			Set tName = $ORDER(tWanted(tName))
			Quit:tName=""
			Set:'$DATA(tHave(tName)) pChanged = pChanged_$SELECT(pChanged '= "": ",", 1: "")_tName
		}
		Quit:pChanged=""
		Do ..SetAgentItem(tItem, .tWanted)
		$$$ThrowOnError(..SaveAndApply(tProd))
		$$$ThrowOnError(##class(AgenticProd.Data.SettingsAudit).Log("productions", pNamespace_" "_pProduction, "agent settings", "", "synced from "_..#AGENTSOURCE_" ("_pChanged_")"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// pList(name) = $LB(target, value) for a new plug-in agent item: AGENTSOURCE's settings here,
/// CodeTable pCodeTable, then pAgentSettings, which may only name AGENTOVERRIDES.
ClassMethod AgentItemSettings(ByRef pAgentSettings, pCodeTable As %String, Output pList) As %Status [ Internal ]
{
	Kill pList
	Do ..AgentSettings(.tSource)
	Quit ..MergeAgentSettings(.tSource, .pAgentSettings, pCodeTable, .pList)
}

ClassMethod MergeAgentSettings(ByRef pSource, ByRef pOverrides, pCodeTable As %String, Output pList) As %Status [ Internal ]
{
	Kill pList
	Set tKey = ""
	For {
		Set tKey = $ORDER(pOverrides(tKey))
		Quit:tKey=""
		Quit:'$LISTFIND($LISTFROMSTRING(..#AGENTOVERRIDES), tKey)
	}
	Quit:tKey'="" $$$ERROR($$$GeneralError, "agent setting "_tKey_" comes from "_..#AGENTSOURCE_"; an install may only set "_..#AGENTOVERRIDES)
	Set i = ""
	For {
		Set i = $ORDER(pSource(i), 1, tSetting)
		Quit:i=""
		Set pList($LIST(tSetting, 1)) = $LISTBUILD($LIST(tSetting, 2), $LIST(tSetting, 3))
	}
	Set pList("CodeTable") = $LISTBUILD("Host", pCodeTable)
	For {
		Set tKey = $ORDER(pOverrides(tKey), 1, tValue)
		Quit:tKey=""
		Set pList(tKey) = $LISTBUILD("Host", tValue)
	}
	Quit $$$OK
}

/// Replace pItem's settings with pList (AgentItemSettings).
ClassMethod SetAgentItem(pItem As Ens.Config.Item, ByRef pList) [ Internal ]
{
	Do pItem.Settings.Clear()
	Set tName = ""
	For {
		Set tName = $ORDER(pList(tName), 1, tSetting)
		Quit:tName=""
		Do ..AddSetting(pItem, tName, $LIST(tSetting, 2), $LIST(tSetting, 1))
	}
}

/// pSettings(n) = $LB(name, target, value) of AGENTSOURCE's settings in this namespace's production.
ClassMethod AgentSettings(Output pSettings) [ Internal ]
{
	Kill pSettings
	Set tProd = ##class(Ens.Config.Production).%OpenId(##class(AgenticProd.Production).%ClassName(1))
	Quit:'$IsObject(tProd)
	Set tItem = tProd.FindItemByConfigName(..#AGENTSOURCE)
	Quit:'$IsObject(tItem)
	For i = 1:1:tItem.Settings.Count() {
		Set tSetting = tItem.Settings.GetAt(i)
		Set pSettings(i) = $LISTBUILD(tSetting.Name, tSetting.Target, tSetting.Value)
	}
}

/// pProd for production pProduction of the current namespace; "" names the one there now.
ClassMethod OpenProduction(ByRef pProduction As %String, Output pProd As Ens.Config.Production) As %Status [ Internal ]
{
	Set pProd = ""
	If pProduction = "" {
		Do ##class(Ens.Director).GetProductionStatus(.pProduction)
		Quit:pProduction="" $$$ERROR($$$GeneralError, "no production in namespace "_$NAMESPACE)
	}
	Set pProd = ##class(Ens.Config.Production).%OpenId(pProduction)
	Set:'$IsObject(pProd) pProd = ##class(Ens.Config.Production).LoadFromClass(pProduction)
	Quit:'$IsObject(pProd) $$$ERROR($$$GeneralError, "cannot open production "_pProduction_" in "_$NAMESPACE)
	Quit $$$OK
}

ClassMethod AddSetting(pItem As Ens.Config.Item, pName As %String, pValue As %String, pTarget As %String = "Host") [ Internal ]
{
	Set tSetting = ##class(Ens.Config.Setting).%New()
	Set tSetting.Name = pName, tSetting.Target = pTarget, tSetting.Value = pValue
	Do pItem.Settings.Insert(tSetting)
}

/// Save pProd, write it back to its class (a production starts from the class), and update the
/// running production so the change takes effect now. UPDATETIMEOUT: an agent job still loading
/// its embedding model takes longer than the default 10 s to stop.
ClassMethod SaveAndApply(pProd As Ens.Config.Production) As %Status [ Internal ]
{
	Set tSC = pProd.%Save()
	Quit:$$$ISERR(tSC) tSC
	Set tSC = pProd.SaveToClass()
	Quit:$$$ISERR(tSC) tSC
	Quit:'##class(Ens.Director).IsProductionRunning(.tRunning) $$$OK
	Quit:tRunning'=pProd.Name $$$OK
	Do ..Mute(.tIO)
	Try {
		Set tSC = ##class(Ens.Director).UpdateProduction(..#UPDATETIMEOUT)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Do ..Unmute(tIO)
	Quit tSC
}

/// Ens.Production.ApplySettings for one setting pName of pItem. An item that saved the value but
/// did not restart in time (the agent item's OnInit is slow) is not an error: pNote says so.
ClassMethod Apply(pProduction As %String, ByRef pSettings, pItem As %String, pName As %String, Output pNote As %String) As %Status [ Internal ]
{
	Set pNote = ""
	Do ..Mute(.tIO)
	Try {
		Set tSC = ##class(Ens.Production).ApplySettings(pProduction, .pSettings)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Do ..Unmute(tIO)
	Quit:$$$ISOK(tSC) $$$OK
	Set tProd = ##class(Ens.Config.Production).%OpenId(pProduction, 0)
	Quit:'$IsObject(tProd) tSC
	Do tProd.%Reload()
	Set tWanted = $GET(pSettings(pItem, "Host", pName))
	If ..ItemSetting(tProd, pItem, pName) '= tWanted Quit tSC
	Set pNote = pItem_" saved, not restarted yet: "_$SYSTEM.Status.GetErrorText(tSC)
	Quit $$$OK
}

/// Output to the null device: Ens.Director writes progress lines to the current device, which in
/// a REST request is the HTTP response. pIO = the device to go back to (Unmute).
ClassMethod Mute(Output pIO As %String) [ Internal ]
{
	Set pIO = $IO
	Set tNull = $SELECT($SYSTEM.Version.GetOS() = "Windows": "//./nul", 1: "/dev/null")
	// A background job's principal device is already the null device; closing it ends the job
	Quit:pIO=tNull
	Open tNull
	Use tNull
}

ClassMethod Unmute(pIO As %String) [ Internal ]
{
	Quit:$IO=pIO
	Set tNull = $IO
	Use pIO
	Close tNull
}

ClassMethod Track(pNamespace As %String, pProduction As %String, pItem As %String, pClass As %String, pMode As %String) As %Status [ Internal ]
{
	Quit:##class(AgenticProd.Data.PluginItem).ItemIdxExists(pNamespace, pProduction, pItem) $$$OK
	Set tRow = ##class(AgenticProd.Data.PluginItem).%New()
	Set tRow.Namespace = pNamespace, tRow.Production = pProduction, tRow.ItemName = pItem
	Set tRow.ClassName = pClass, tRow.Mode = pMode
	Quit tRow.%Save()
}

}
