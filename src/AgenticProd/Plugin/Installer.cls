Include Ensemble

/// Adds the AI plug-in (Sentinel, Triage, agent) to an existing production in another namespace
/// and takes it out again. Only touches the production through Ens.Config.Production, and every
/// item it adds is tracked in Data.PluginItem, so Disable removes exactly those. The namespace
/// needs the AgenticProd mappings and grants first (Setup.LegacyMappings, AgentSecurity).
Class AgenticProd.Plugin.Installer
{

/// Config name prefix of every plug-in item; the Sentinel skips messages to and from them.
Parameter PREFIX = "AI.";

/// Config name suffix = class of each item Enable adds, in production order.
Parameter ITEMS = "Sentinel=AgenticProd.Plugin.Sentinel,Triage=AgenticProd.Process.Triage,Agent=AgenticProd.Operation.Agent";

/// Agent item in this namespace's production whose settings (provider, model, budgets) the
/// plug-in agent starts with.
Parameter AGENTSOURCE = "TriageAgent";

Parameter UPDATETIMEOUT = 60;

/// Modes Enable accepts. propose and act come with 8.5.
Parameter MODES = "observe";

/// Add the plug-in items to pProduction in pNamespace (default: the production there now) and
/// apply them if it is running. pAdded = item names added. Running it again adds only what is
/// missing; an item of the same name that the plug-in did not add is an error, nothing is changed.
/// pAgentSettings(name) = value overrides the copied agent settings (e.g. KillSwitch=1 installs
/// it with the AI off).
ClassMethod Enable(pNamespace As %String, pProduction As %String = "", pMode As %String = "observe", Output pAdded As %String, ByRef pAgentSettings) As %Status
{
	Set pAdded = ""
	Set tSC = $$$OK
	Try {
		If '$LISTFIND($LISTFROMSTRING(..#MODES), pMode) $$$ThrowStatus($$$ERROR($$$GeneralError, "mode must be one of "_..#MODES_", not '"_pMode_"'"))
		If pNamespace = $NAMESPACE $$$ThrowStatus($$$ERROR($$$GeneralError, "the plug-in goes into another namespace's production, not "_$NAMESPACE))
		Do ..AgentSettings(.tAgentSettings)
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		For i = 1:1:$LENGTH(..#ITEMS, ",") {
			Set tPair = $PIECE(..#ITEMS, ",", i), tName = ..#PREFIX_$PIECE(tPair, "="), tClass = $PIECE(tPair, "=", 2)
			If $IsObject(tProd.FindItemByConfigName(tName)) {
				// Someone else's item with our name: tracking it would let Disable remove it
				If '##class(AgenticProd.Data.PluginItem).ItemIdxExists(pNamespace, pProduction, tName) $$$ThrowStatus($$$ERROR($$$GeneralError, pProduction_" already has an item "_tName_" the plug-in did not add"))
			} Else {
				Set tItem = ##class(Ens.Config.Item).%New()
				Set tItem.Name = tName, tItem.ClassName = tClass, tItem.PoolSize = 1, tItem.Enabled = 1
				Set tItem.Category = "AgenticProd plug-in", tItem.Comment = "Added by AgenticProd.Plugin.Installer ("_pMode_"); Disable removes it"
				If tName = (..#PREFIX_"Sentinel") {
					Do ..AddSetting(tItem, "TargetConfigName", ..#PREFIX_"Triage")
				} ElseIf tName = (..#PREFIX_"Triage") {
					Do ..AddSetting(tItem, "AgentTarget", ..#PREFIX_"Agent")
					Do ..AddSetting(tItem, "ActionMode", pMode)
				} Else {
					Set tKey = ""
					For {
						Set tKey = $ORDER(tAgentSettings(tKey), 1, tSetting)
						Quit:tKey=""
						Continue:$DATA(pAgentSettings($LIST(tSetting, 1)))
						Do ..AddSetting(tItem, $LIST(tSetting, 1), $LIST(tSetting, 3), $LIST(tSetting, 2))
					}
					Set tKey = ""
					For {
						Set tKey = $ORDER(pAgentSettings(tKey), 1, tValue)
						Quit:tKey=""
						Do ..AddSetting(tItem, tKey, tValue)
					}
				}
				Do tProd.Items.Insert(tItem)
				// Marks left by an earlier install would make a new Sentinel rescan from there
				Kill $$$EnsStaticAppData(tName)
				Set pAdded = pAdded_$SELECT(pAdded '= "": ",", 1: "")_tName
			}
			$$$ThrowOnError(..Track(pNamespace, pProduction, tName, tClass, pMode))
		}
		Quit:pAdded=""
		$$$ThrowOnError(..SaveAndApply(tProd))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Remove every tracked plug-in item from pProduction in pNamespace, apply that if it is
/// running, and drop the tracking rows. pRemoved = item names removed. Items the installer did
/// not add are never touched, whatever their name.
ClassMethod Disable(pNamespace As %String, pProduction As %String = "", Output pRemoved As %String) As %Status
{
	Set pRemoved = ""
	Set tSC = $$$OK
	Try {
		New $NAMESPACE
		Set $NAMESPACE = pNamespace
		$$$ThrowOnError(..OpenProduction(.pProduction, .tProd))
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ItemName FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ?", pNamespace, pProduction)
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
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
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
	Quit ##class(Ens.Director).UpdateProduction(..#UPDATETIMEOUT)
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
