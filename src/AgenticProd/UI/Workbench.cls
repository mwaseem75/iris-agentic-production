Include Ensemble

/// Data behind the AI Hub Workbench page: the Library of AI Hub classes in this namespace and
/// the read-only map of a production. Reads dictionary, production config and logs; changes nothing.
Class AgenticProd.UI.Workbench Extends %RegisteredObject
{

/// System namespaces with productions we never list.
Parameter SKIPNS = "ENSLIB,HSLIB,HSSYS,HSCUSTOM,HSAUX,DOCBOOK";

/// Classes the Library never shows: the Settings page's ping agent and the shared agent base are plumbing, not building blocks.
Parameter HIDE = "AgenticProd.Agent.PingAgent,AgenticProd.Agent.Base";

/// The host operation class and the agent class it runs.
Parameter HOSTCLASS = "AgenticProd.Operation.Agent";

Parameter AGENTCLASS = "AgenticProd.Agent.TriageAgent";

/// Plain IRIS checks that run around the agent. Not AI Hub classes, so they are listed by hand.
/// class|name|description
Parameter CHECKS = "AgenticProd.Policy.InjectionGuard|Injection guard|Flags instruction-like text in a message, which stops AUTO_FIX.;AgenticProd.Tools.HL7|Grounding gate|Every claim in a decision must come from the message or a tool result.";

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
	Set tHomeDb = ##class(%SYS.Namespace).GetRoutineDest(pNs)
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Super [ 'Ens.Production' AND Name NOT LIKE 'Ens%' AND Name NOT LIKE 'HS.%'")
		While tRS.%Next() {
			// Packages mapped in from another database (IRISAPP's AgenticProd) are not this namespace's own productions
			Continue:(##class(%SYS.Namespace).GetPackageDest(pNs, $PIECE(tRS.Name, ".", 1)) '= tHomeDb)
			Set tNames(tRS.Name) = ""
		}
	} Catch {}
	Set tName = ""
	For {
		Set tName = $ORDER(tNames(tName))
		Quit:tName=""
		// A production with no items is an empty shell, nothing to map
		Set tCfg = ##class(Ens.Config.Production).%OpenId(tName)
		Set:'$IsObject(tCfg) tCfg = ##class(Ens.Config.Production).LoadFromClass(tName)
		Continue:('$IsObject(tCfg) || 'tCfg.Items.Count())
		Set tP = {"name":(tName)}
		Do tP.%Set("current", ''(tName = tCurrent), "boolean")
		Do tP.%Set("running", ''((tName = tCurrent) && (tState = $$$eProductionStateRunning)), "boolean")
		Do tRow.productions.%Push(tP)
	}
	Quit tRow
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

/// Map of one production: items with 24 h numbers, links between them and, for each item that
/// hosts an AI Hub agent, the agent's parts. Returns "" when the production does not exist.
ClassMethod Production(pNs As %String, pName As %String) As %DynamicObject
{
	// Plug-in rows are in the home namespace; the other namespace may not map our classes
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ItemName, Owner FROM AgenticProd_Data.PluginItem WHERE Namespace = ? AND Production = ?", pNs, pName)
	// Items the installers added; only the ones that host an agent count as AI Hub
	While tRS.%Next() { Set tAI(tRS.ItemName) = $SELECT(tRS.Owner '= "": "Workbench", 1: "plug-in") }
	Set tInstalls = ##class(AgenticProd.Plugin.AddAgent).Installs("", pNs, pName)
	Set tHome = $NAMESPACE
	Set tNow = $ZTIMESTAMP, tSince = $ZDATETIME((tNow - 1)_","_$PIECE(tNow, ",", 2), 3)
	Set tUsage = ..Usage24h(pNs, tSince)
	New $NAMESPACE
	Set $NAMESPACE = pNs
	Set tProd = ##class(Ens.Config.Production).%OpenId(pName)
	Set:'$IsObject(tProd) tProd = ##class(Ens.Config.Production).LoadFromClass(pName)
	Quit:'$IsObject(tProd) ""
	Do ##class(Ens.Director).GetProductionStatus(.tCurrent, .tState)
	Set tOut = {"namespace":(pNs), "name":(pName), "items":[], "connections":[], "hosts":[], "usage24h":(tUsage), "installs":(tInstalls)}
	Do tOut.%Set("running", ''((pName = tCurrent) && (tState = $$$eProductionStateRunning)), "boolean")
	Set tAiCount = 0
	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i)
		Set tClass = tItem.ClassName
		Set tRow = {"name":(tItem.Name), "class":(tClass), "type":(..TypeOf(tClass)), "category":(tItem.Category)}
		Do tRow.%Set("enabled", ''tItem.Enabled, "boolean")
		If (tClass = "AgenticProd.Operation.FhirOut"), '##class(AgenticProd.Paths).FhirAvailable() {
			Set tRow.note = ##class(AgenticProd.Paths).#FHIRNOTE
		}
		// Plug-in namespaces may not map our classes, so the host is also recognised by name
		Set tHost = (tClass = ..#HOSTCLASS) || ..IsHost(tClass)
		Set tIsAI = ''tHost
		Do tRow.%Set("ai", tIsAI, "boolean")
		Set tRow.added = $SELECT($DATA(tAI(tItem.Name)) && 'tHost: tAI(tItem.Name), 1: "")
		Do tRow.%Set("checks", ''(tClass = "AgenticProd.Process.Triage"), "boolean")
		Set tAiCount = tAiCount + tIsAI
		Set tHealth = ..ItemHealth(tItem.Name, tSince)
		Set tRow.errors24h = tHealth.errors24h, tRow.suspended = tHealth.suspended, tRow.lastError = tHealth.lastError, tRow.in24h = tHealth.in24h, tRow.sent24h = tHealth.sent24h
		Do tOut.items.%Push(tRow)
		Do:tHost tOut.hosts.%Push(..Host(tItem, tUsage, tSince, tHome, pNs))
		Set tNames(tItem.Name) = ""
		For j = 1:1:tItem.Settings.Count() {
			Set tSet = tItem.Settings.GetAt(j)
			Set:(tSet.Name = "WatchItems") tRow.watches = tSet.Value
			// TargetConfigName(s) plus the named targets of our hosts (TriageTarget, FHIRTarget, AgentTarget)
			If (tSet.Name = "TargetConfigName") || (tSet.Name = "TargetConfigNames") || ($EXTRACT(tSet.Name, *-5, *) = "Target") {
				Do ..AddLinks(tItem.Name, tSet.Value, .tLink)
			} ElseIf (tSet.Name = "BusinessRuleName") && (tSet.Value '= "") {
				Do ..AddLinks(tItem.Name, ..RuleTargets(tSet.Value), .tLink)
			}
		}
	}
	Do ..ObservedLinks(.tNames, .tLink)
	Set tFrom = ""
	For {
		Set tFrom = $ORDER(tLink(tFrom))
		Quit:tFrom=""
		Set tTo = ""
		For {
			Set tTo = $ORDER(tLink(tFrom, tTo))
			Quit:tTo=""
			// Rule and setting targets can name things that are not items (a workflow role)
			Do:$DATA(tNames(tTo)) tOut.connections.%Push({"from":(tFrom), "to":(tTo)})
		}
	}
	Set tOut.aiItems = tAiCount, tOut.totalItems = tProd.Items.Count()
	Quit tOut
}

/// Adds the comma-separated targets of one item to the link set.
ClassMethod AddLinks(pFrom As %String, pList As %String, ByRef pLink) [ Internal ]
{
	Set tList = $TRANSLATE(pList, " ", "")
	For k = 1:1:$LENGTH(tList, ",") {
		Set tTo = $PIECE(tList, ",", k)
		Set:((tTo '= "") && (tTo '= pFrom)) pLink(pFrom, tTo) = ""
	}
}

/// Targets named in a routing rule: every target="..." of its RuleDefinition (send actions).
/// Read in the production's namespace; a rule that is not a class gives "".
ClassMethod RuleTargets(pRule As %String) As %String [ Internal ]
{
	Set tOut = ""
	Try {
		If ##class(%Dictionary.CompiledXData).%ExistsId(pRule_"||RuleDefinition") {
			Set tText = ##class(%Dictionary.CompiledXData).%OpenId(pRule_"||RuleDefinition").Data.Read(3000000)
			Set tMatcher = ##class(%Regex.Matcher).%New("target=""([^""]*)""", tText)
			While tMatcher.Locate() { Set tOut = tOut_","_tMatcher.Group(1) }
		}
	} Catch {}
	Quit tOut
}

/// Source to target pairs of request messages in the last 7 days, between items of this production.
ClassMethod ObservedLinks(ByRef pNames, ByRef pLink) [ Internal ]
{
	Try {
		Set tNow = $ZTIMESTAMP, tWeek = $ZDATETIME((tNow - 7)_","_$PIECE(tNow, ",", 2), 3)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT SourceConfigName, TargetConfigName FROM Ens.MessageHeader WHERE Type = 1 AND TimeCreated >= ?", tWeek)
		While tRS.%Next() {
			Set tA = tRS.%GetData(1), tB = tRS.%GetData(2)
			Set:((tA '= tB) && $DATA(pNames(tA)) && $DATA(pNames(tB))) pLink(tA, tB) = ""
		}
	} Catch {}
}

/// True for the operation class that runs a declarative agent.
ClassMethod IsHost(pClass As %String) As %Boolean [ Internal ]
{
	Quit:pClass="" 0
	Quit ##class(%Dictionary.CompiledClass).%ExistsId(pClass) && ..Extends(pClass, ..#HOSTCLASS)
}

ClassMethod Extends(pClass As %String, pBase As %String) As %Boolean [ Internal ]
{
	Set tYes = 0
	Try { Set tYes = ''$CLASSMETHOD(pClass, "%Extends", pBase) } Catch {}
	Quit tYes
}

/// Agent runs, tool calls, tokens and cost of the last 24 h in one namespace. Usage rows carry
/// the namespace, not an agent name. Replays are not real runs.
ClassMethod Usage24h(pNs As %String, pSince As %String) As %DynamicObject [ Internal ]
{
	Set tOut = {"runs":0, "toolCalls":0, "tokens":0, "costUsd":0, "denied":0}
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), SUM(ToolCalls), SUM(PromptTokens + CompletionTokens), SUM(CostUsd) FROM AgenticProd_Data.Usage WHERE Replay = 0 AND Namespace = ? AND CreatedAt >= ?", pNs, pSince)
		If tRS.%Next() Set tOut.runs = +tRS.%GetData(1), tOut.toolCalls = +tRS.%GetData(2), tOut.tokens = +tRS.%GetData(3), tOut.costUsd = +tRS.%GetData(4)
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM AgenticProd_Data.ToolCall WHERE Status = 'DENIED' AND Namespace = ? AND CreatedAt >= ?", pNs, pSince)
		If tRS.%Next() Set tOut.denied = +tRS.%GetData(1)
	} Catch {}
	Quit tOut
}

/// Messages, errors and suspended messages of one item, read in the current namespace.
ClassMethod ItemHealth(pItem As %String, pSince As %String) As %DynamicObject [ Internal ]
{
	Set tOut = {"in24h":0, "sent24h":0, "errors24h":0, "suspended":0, "lastError":""}
	// Plain SQL: the namespace may not map AgenticProd classes
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName = ? AND TimeCreated >= ?", pItem, pSince)
		If tRS.%Next() Set tOut.in24h = +tRS.%GetData(1)
		// Services receive no messages from inside the production; they send
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND Type = 1 AND TimeCreated >= ?", pItem, pSince)
		If tRS.%Next() Set tOut.sent24h = +tRS.%GetData(1)
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

/// The AI Hub card and component circles of one host item.
ClassMethod Host(pItem As Ens.Config.Item, pUsage As %DynamicObject, pSince As %String, pHome As %String, pNs As %String) As %DynamicObject [ Internal ]
{
	// Our classes and tool-call rows live in the home namespace
	New $NAMESPACE
	Set $NAMESPACE = pHome
	Set tAgent = ..#AGENTCLASS
	Set tProvider = "", tModelSetting = "", tDisabled = ""
	For j = 1:1:pItem.Settings.Count() {
		Set tSet = pItem.Settings.GetAt(j)
		Set:tSet.Name="ProviderConfig" tProvider = tSet.Value
		Set:tSet.Name="Model" tModelSetting = tSet.Value
		Set:tSet.Name="DisabledSkills" tDisabled = tSet.Value
	}
	// An Add to production install hosts its own agent class
	For j = 1:1:pItem.Settings.Count() {
		Set tSet = pItem.Settings.GetAt(j)
		If (tSet.Name = "AgentClass") && (tSet.Value '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(tSet.Value) Set tAgent = tSet.Value
	}
	Set tHost = {"item":(pItem.Name), "operation":(pItem.ClassName), "agentClass":(tAgent), "usage":(pUsage), "components":[]}
	Set tKey = ..KeySource($PARAMETER(tAgent, "APIKEY"), tProvider)
	Set tModel = $SELECT(tModelSetting'="": tModelSetting, 1: $PARAMETER(tAgent, "MODEL"))
	Do tHost.components.%Push({"id":"model", "kind":"model", "title":(tModel), "sub":("key: "_tKey), "class":(tAgent), "detail":("Provider "_$PARAMETER(tAgent, "PROVIDER")_", key from "_tKey), "usedBy":[($PIECE(tAgent, ".", *))], "tools":[], "calls24h":(pUsage.runs)})
	Set tCalls = ..CallsByTool(pSince, pNs)
	Set tToolsets = $PARAMETER(tAgent, "TOOLSETS")
	For i = 1:1:$LENGTH(tToolsets, ",") {
		Set tClass = $ZSTRIP($PIECE(tToolsets, ",", i), "<>W")
		Continue:tClass=""
		Set tDef = ..ToolSetInfo(tClass)
		Do tHost.components.%Push({"id":(tClass), "kind":"toolset", "title":(tDef.name), "sub":($PIECE(tClass, ".", *)_" · "_tDef.tools.%Size()_" tools"), "class":(tClass), "detail":(tDef.description), "usedBy":[($PIECE(tAgent, ".", *))], "tools":(tDef.tools), "calls24h":(..CallsFor(tDef.tools, tCalls))})
	}
	// Operation.Agent applies DisabledSkills to the triage agent only
	Set tSkills = ..ActiveSkills($PARAMETER(tAgent, "SKILLS"), $SELECT(tAgent = ..#AGENTCLASS: tDisabled, 1: ""))
	For i = 1:1:$LENGTH(tSkills, ",") {
		Set tClass = $PIECE(tSkills, ",", i)
		Continue:tClass=""
		Set tSk = ..SkillInfo(tClass)
		Do tHost.components.%Push({"id":(tClass), "kind":"skill", "title":(tSk.name), "sub":("+ "_tSk.toolsetNames_" ("_tSk.tools.%Size()_")"), "class":(tClass), "detail":(tSk.description), "usedBy":[($PIECE(tAgent, ".", *))], "tools":(tSk.tools), "calls24h":(..CallsFor(tSk.tools, tCalls))})
	}
	// Knowledge counts when a tool the agent really has (its tool sets, its skills' tool sets) searches it
	Set tHasLoinc = 0, tSets = tToolsets
	For i = 1:1:$LENGTH(tSkills, ",") { Set tSets = tSets_","_$PARAMETER($PIECE(tSkills, ",", i), "TOOLS") }
	For i = 1:1:$LENGTH(tSets, ",") {
		Set tTs = $ZSTRIP($PIECE(tSets, ",", i), "<>W")
		Set:((tTs'="") && (..SourceText(tTs) [ "search_loinc")) tHasLoinc = 1
	}
	If tHasLoinc {
		Do tHost.components.%Push({"id":"search_loinc", "kind":"knowledge", "title":"LOINC subset", "sub":"search_loinc", "class":"search_loinc", "detail":"Vector search over the LOINC lab codes, used when mapping a code.", "usedBy":[($PIECE(tAgent, ".", *))], "tools":["search_loinc"], "calls24h":(..CallsFor(["search_loinc"], tCalls))})
	}
	// Operation.Agent.BuildAgent: the class's own policy when it names one, else the host's ReadOnly and Audit
	Set tAuth = $PARAMETER(tAgent, "AUTHPOLICY"), tAudit = $PARAMETER(tAgent, "AUDITPOLICY")
	Set:tAuth="" tAuth = "AgenticProd.Policy.ReadOnly"
	Set:tAudit="" tAudit = "AgenticProd.Policy.Audit"
	Set tIter = ..AgentClassesOf("%AI.Policy.Authorization,%AI.Policy.Audit").%GetIterator()
	While tIter.%GetNext(, .tPol) {
		Continue:((tPol.class '= tAuth) && (tPol.class '= tAudit))
		Do tHost.components.%Push({"id":(tPol.class), "kind":"policy", "title":(tPol.name), "sub":(tPol.kind), "class":(tPol.class), "detail":(tPol.description), "usedBy":[($PIECE(tAgent, ".", *))], "tools":[], "calls24h":0})
	}
	Quit tHost
}

/// Display text of an APIKEY parameter, or of the provider config that replaces it.
ClassMethod KeySource(pApiKey As %String, pProvider As %String) As %String [ Internal ]
{
	Quit:pProvider'="" "provider config "_pProvider
	If pApiKey ?1"@{env:".E1"}" Quit ".env ("_$EXTRACT(pApiKey, 7, *-1)_")"
	Quit:pApiKey="" "none"
	Quit "set in the class"
}

/// Skills of an agent minus the ones left out for this item.
ClassMethod ActiveSkills(pAll As %String, pDisabled As %String) As %String [ Internal ]
{
	Set tOut = "", tOff = ","_$TRANSLATE(pDisabled, " ", "")_","
	For i = 1:1:$LENGTH(pAll, ",") {
		Set tClass = $ZSTRIP($PIECE(pAll, ",", i), "<>W")
		Set:(tClass'="")&&(tOff'[(","_tClass_",")) tOut = tOut_$SELECT(tOut="": "", 1: ",")_tClass
	}
	Quit tOut
}

/// Tool calls in the last 24 h for the production's namespace, by tool name. load_skill is not
/// audited by AI Hub, so skills are counted by calls of the tools they add.
ClassMethod CallsByTool(pSince As %String, pNs As %String) As %String [ Internal ]
{
	Kill tCalls
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, COUNT(*) FROM AgenticProd_Data.ToolCall WHERE Namespace = ? AND CreatedAt >= ? GROUP BY Tool", pNs, pSince)
		While tRS.%Next() { Set tCalls(tRS.%GetData(1)) = +tRS.%GetData(2) }
	} Catch {}
	Quit ..Pack(.tCalls)
}

/// Array to a string that survives being passed as a value (tool=n;tool=n).
ClassMethod Pack(ByRef pArr) As %String [ Internal ]
{
	Set tOut = "", tK = ""
	For {
		Set tK = $ORDER(pArr(tK))
		Quit:tK=""
		Set tOut = tOut_tK_"="_pArr(tK)_";"
	}
	Quit tOut
}

ClassMethod CallsFor(pTools As %DynamicArray, pPacked As %String) As %Integer [ Internal ]
{
	Set tSum = 0, tIter = pTools.%GetIterator()
	While tIter.%GetNext(, .tName) {
		// ToolCall stores tool names in upper case
		Set tName = $ZCONVERT(tName, "U"), tAt = $FIND(";"_pPacked, ";"_tName_"=")
		Set:tAt tSum = tSum + +$PIECE($EXTRACT(";"_pPacked, tAt, *), ";", 1)
	}
	Quit tSum
}

/// Name, description and tool names of a ToolSet class, from its Definition XData.
ClassMethod ToolSetInfo(pClass As %String) As %DynamicObject [ Internal ]
{
	Set tOut = {"name":($PIECE(pClass, ".", *)), "description":"", "tools":[], "toolDescriptions":[]}
	Set tXml = ##class(AgenticProd.Settings.Store).XDataText(pClass, "Definition")
	Set tName = $PIECE($PIECE(tXml, "<ToolSet Name=""", 2), """", 1)
	Set:tName'="" tOut.name = tName
	// First <Description> is the set's own, the rest follow their <Tool>
	Set tOut.description = ..Unescape($PIECE($PIECE(tXml, "<Description>", 2), "</Description>", 1))
	Set tParts = $LENGTH(tXml, "<Tool Name=""")
	For i = 2:1:tParts {
		Set tPart = $PIECE(tXml, "<Tool Name=""", i)
		Do tOut.tools.%Push($PIECE(tPart, """", 1))
		Do tOut.toolDescriptions.%Push(..Unescape($PIECE($PIECE(tPart, "<Description>", 2), "</Description>", 1)))
	}
	// <Query> tools: the description is an attribute
	Set tParts = $LENGTH(tXml, "<Query Name=""")
	For i = 2:1:tParts {
		Set tPart = $PIECE(tXml, "<Query Name=""", i)
		Do tOut.tools.%Push($PIECE(tPart, """", 1))
		Do tOut.toolDescriptions.%Push($ZCONVERT($PIECE($PIECE(tPart, "Description=""", 2), """", 1), "I", "XML"))
	}
	Set:((tOut.description = "") && tOut.toolDescriptions.%Size()) tOut.description = tOut.toolDescriptions.%Get(0)
	Quit tOut
}

ClassMethod Unescape(pText As %String) As %String [ Internal ]
{
	Quit $REPLACE($REPLACE($REPLACE($ZSTRIP(pText, "<>W"), "&lt;", "<"), "&gt;", ">"), "&amp;", "&")
}

/// Name, description (the model reads it to decide when to load the skill) and the tools it adds.
ClassMethod SkillInfo(pClass As %String) As %DynamicObject [ Internal ]
{
	Set tOut = {"class":(pClass), "name":($PIECE(pClass, ".", *)), "description":"", "tools":[], "toolsetNames":"", "toolsets":[]}
	Set tLines = $TRANSLATE(##class(AgenticProd.Settings.Store).XDataText(pClass, "SUMMARY"), $CHAR(13))
	For j = 1:1:$LENGTH(tLines, $CHAR(10)) {
		Set tLine = $PIECE(tLines, $CHAR(10), j), tKey = $ZSTRIP($PIECE(tLine, ":"), "<>W")
		Do:(tKey="name")||(tKey="description") tOut.%Set(tKey, $ZSTRIP($PIECE(tLine, ":", 2, *), "<>W", """"))
	}
	Set tTools = $PARAMETER(pClass, "TOOLS")
	For i = 1:1:$LENGTH(tTools, ",") {
		Set tTs = $ZSTRIP($PIECE(tTools, ",", i), "<>W")
		Continue:tTs=""
		Set tInfo = ..ToolSetInfo(tTs)
		Do tOut.toolsets.%Push(tTs)
		Set tOut.toolsetNames = tOut.toolsetNames_$SELECT(tOut.toolsetNames="": "", 1: ", ")_tInfo.name
		Set tIter = tInfo.tools.%GetIterator()
		While tIter.%GetNext(, .tTool) { Do tOut.tools.%Push(tTool) }
	}
	Quit tOut
}

/// Source text of a class, "" when it cannot be read.
ClassMethod SourceText(pClass As %String) As %String [ Internal ]
{
	Set tText = ""
	Try {
		Do ##class(%Compiler.UDL.TextServices).GetTextAsArray($NAMESPACE, pClass, .tLines)
		Set i = ""
		For {
			Set i = $ORDER(tLines(i))
			Quit:i=""
			Set tText = tText_tLines(i)_$CHAR(10)
		}
	} Catch {}
	Quit tText
}

/// Every non-system class in this namespace that extends one of the comma-separated bases, with
/// its short description. Test classes, abstract classes and HIDE are left out.
ClassMethod AgentClassesOf(pBases As %String) As %DynamicArray [ Internal ]
{
	Set tOut = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Abstract, Description, Super FROM %Dictionary.CompiledClass WHERE Name NOT LIKE '|%%' ESCAPE '|' AND Name NOT LIKE 'Ens%' AND Name NOT LIKE 'HS%' AND Name NOT LIKE 'IrisDevTmp%' AND Name NOT LIKE '%.Test.%' AND Name NOT LIKE 'MyAI.WbTest.%' ORDER BY Name")
	While tRS.%Next() {
		Set tName = tRS.Name
		Continue:tRS.Abstract||((","_..#HIDE_",")[(","_tName_","))
		Continue:tRS.Super=""
		For i = 1:1:$LENGTH(pBases, ",") {
			Set tBase = $PIECE(pBases, ",", i)
			If ..Extends(tName, tBase) {
				Do tOut.%Push({"class":(tName), "name":($PIECE(tName, ".", *)), "description":(..FirstLine(tRS.Description)), "base":(tBase), "kind":($CASE(tBase, "%AI.Policy.Authorization":"authorization", "%AI.Policy.Audit":"audit", :""))})
				Quit
			}
		}
	}
	Quit tOut
}

/// First sentence of a class comment, one line.
ClassMethod FirstLine(pText As %String) As %String [ Internal ]
{
	Set tText = $ZSTRIP($TRANSLATE(pText, $CHAR(13,10), "  "), "<>W")
	Set tEnd = $FIND(tText, ". ")
	Set:tEnd tText = $EXTRACT(tText, 1, tEnd - 2)
	// One full stop, whether or not the comment already ended with one
	Set tText = $ZSTRIP(tText, ">", ".")
	Set:tText'="" tText = tText_"."
	Quit $EXTRACT(tText, 1, 200)
}

/// The Library: every AI Hub class in this namespace with a short description and what uses it.
ClassMethod Library() As %DynamicObject
{
	Set tOut = {"agents":[], "toolsets":[], "skills":[], "policies":[], "knowledge":[], "checks":[]}
	Set tAgents = ..AgentClassesOf("%AI.Agent")
	Set tSkillRows = ..AgentClassesOf("%AI.Agent.Skill")
	Set tSkillSet = ","
	Set tIter = tSkillRows.%GetIterator()
	While tIter.%GetNext(, .tS) { Set tSkillSet = tSkillSet_tS.class_"," }
	// Skills extend %AI.ToolSet too; they are listed as skills only
	Set tSets = ..AgentClassesOf("%AI.ToolSet")
	Set tHostText = ..SourceText(..#HOSTCLASS)
	Set tHostItem = $PIECE(..#HOSTCLASS, ".", *)
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Name FROM Ens_Config.Item WHERE ClassName = ?", ..#HOSTCLASS)
		Set:tRS.%Next() tHostItem = tRS.%GetData(1)
	} Catch {}
	Set tMapText = ""
	// usedBy[tClass] lists the agents or skills that name the class
	Set tIter = tAgents.%GetIterator()
	While tIter.%GetNext(, .tA) {
		Set tAC = tA.class, tToolsets = $PARAMETER(tAC, "TOOLSETS"), tSkills = $PARAMETER(tAC, "SKILLS")
		For i = 1:1:$LENGTH(tToolsets, ",") { Set tC = $ZSTRIP($PIECE(tToolsets, ",", i), "<>W")  Set:tC'="" tUsed(tC, tA.name) = "" }
		For i = 1:1:$LENGTH(tSkills, ",") {
			Set tC = $ZSTRIP($PIECE(tSkills, ",", i), "<>W")
			Continue:tC=""
			Set tUsed(tC, tA.name) = ""
			Set tTools = $PARAMETER(tC, "TOOLS")
			For j = 1:1:$LENGTH(tTools, ",") { Set tT = $ZSTRIP($PIECE(tTools, ",", j), "<>W")  Set:tT'="" tVia(tT, $PIECE(tC, ".", *)) = "" }
		}
		Set tHosted = ($LENGTH(tHostText) && (tHostText [ tAC))
		Set tInfo = {"class":(tAC), "name":(tA.name), "description":(tA.description), "provider":($PARAMETER(tAC, "PROVIDER")), "model":($PARAMETER(tAC, "MODEL")), "toolsets":(..CountList(tToolsets)), "skills":(..CountList(tSkills))}
		Set tInfo.hostedBy = $SELECT(tHosted: tHostItem, 1: "")
		Set tInfo.installs = ##class(AgenticProd.Plugin.AddAgent).Installs(tAC)
		Do tOut.agents.%Push(tInfo)
	}
	Set tIter = tSets.%GetIterator()
	While tIter.%GetNext(, .tT) {
		Continue:(tSkillSet [ (","_tT.class_","))
		Set tDef = ..ToolSetInfo(tT.class)
		Set tUsers = ..Join(.tUsed, tT.class), tVias = ..Join(.tVia, tT.class)
		Set tUse = $SELECT(tUsers'="": "used by "_tUsers, 1: "")
		Set:tVias'="" tUse = tUse_$SELECT(tUse="": "", 1: " · ")_"via skill "_tVias
		Do tOut.toolsets.%Push({"class":(tT.class), "name":(tDef.name), "description":(tDef.description), "tools":(tDef.tools), "toolDescriptions":(tDef.toolDescriptions), "readOnly":(..ReadOnlyTools(tT.class)), "usedBy":(tUse)})
		Set:(..SourceText(tT.class) [ "search_loinc") tMapText = tMapText_tT.class_","
	}
	Set tIter = tSkillRows.%GetIterator()
	While tIter.%GetNext(, .tS) {
		Set tSk = ..SkillInfo(tS.class)
		Do tOut.skills.%Push({"class":(tS.class), "name":(tSk.name), "description":(tSk.description), "tools":(tSk.tools), "toolsets":(tSk.toolsetNames), "usedBy":(..UsedLine(.tUsed, tS.class))})
	}
	Set tIter = ..AgentClassesOf("%AI.Policy.Authorization,%AI.Policy.Audit").%GetIterator()
	While tIter.%GetNext(, .tP) {
		Set tUsers = ""
		If tHostText [ tP.class { Set tUsers = "used by "_..AgentNames(tAgents) }
		Do tOut.policies.%Push({"class":(tP.class), "name":(tP.name), "description":(tP.kind_" · "_tP.description), "kind":(tP.kind), "usedBy":(tUsers)})
	}
	Set tLoincUse = ""
	For i = 1:1:$LENGTH(tMapText, ",") - 1 {
		Set tC = $PIECE(tMapText, ",", i), tVias = ..Join(.tVia, tC)
		Set tLoincUse = $SELECT(..UsedLine(.tUsed, tC)'="": ..UsedLine(.tUsed, tC), tVias'="": "via skill "_tVias, 1: tLoincUse)
	}
	Do:..HasLoinc() tOut.knowledge.%Push({"class":"search_loinc", "name":"LOINC subset", "description":"Vector search over the LOINC lab codes the agent maps local codes to. Local FastEmbed vectors, no LLM call.", "usedBy":(tLoincUse)})
	For i = 1:1:$LENGTH(..#CHECKS, ";") {
		Set tRow = $PIECE(..#CHECKS, ";", i)
		Do tOut.checks.%Push({"class":($PIECE(tRow, "|", 1)), "name":($PIECE(tRow, "|", 2)), "description":($PIECE(tRow, "|", 3)), "plain":true, "usedBy":"runs in the Triage process"})
	}
	Quit tOut
}

ClassMethod CountList(pList As %String) As %Integer [ Internal ]
{
	Set tN = 0
	For i = 1:1:$LENGTH(pList, ",") { Set:$ZSTRIP($PIECE(pList, ",", i), "<>W")'="" tN = tN + 1 }
	Quit tN
}

/// Comma list of the second subscripts under pArr(pKey).
ClassMethod Join(ByRef pArr, pKey As %String) As %String [ Internal ]
{
	Set tOut = "", tK = ""
	For {
		Set tK = $ORDER(pArr(pKey, tK))
		Quit:tK=""
		Set tOut = tOut_$SELECT(tOut="": "", 1: ", ")_tK
	}
	Quit tOut
}

ClassMethod UsedLine(ByRef pArr, pKey As %String) As %String [ Internal ]
{
	Set tUsers = ..Join(.pArr, pKey)
	Quit $SELECT(tUsers="": "", 1: "used by "_tUsers)
}

ClassMethod AgentNames(pAgents As %DynamicArray) As %String [ Internal ]
{
	Set tOut = "", tIter = pAgents.%GetIterator()
	While tIter.%GetNext(, .tA) { Set tOut = tOut_$SELECT(tOut="": "", 1: ", ")_tA.name }
	Quit tOut
}

/// Every tool of the class is read-only unless the class asks for authorization.
ClassMethod ReadOnlyTools(pClass As %String) As %Boolean [ Internal ]
{
	Set tRO = 1
	Try { Set:+$PARAMETER(pClass, "REQUIRESAUTH") tRO = 0 } Catch {}
	Quit tRO
}

ClassMethod HasLoinc() As %Boolean [ Internal ]
{
	Quit ''##class(%Dictionary.CompiledClass).%ExistsId("AgenticProd.Tools.Mapping")
}

/// Read-only source of one Library class. "" when the class is not in the Library, so the page
/// cannot be used to read arbitrary classes.
ClassMethod Source(pClass As %String) As %DynamicObject
{
	Set tLib = ..Library(), tOk = 0
	For tList = "agents", "toolsets", "skills", "policies", "checks" {
		Set tIter = $PROPERTY(tLib, tList).%GetIterator()
		While tIter.%GetNext(, .tRow) { Set:tRow.class=pClass tOk = 1 }
	}
	Quit:'tOk ""
	Quit {"class":(pClass), "source":(..WithoutSpec(..SourceText(pClass)))}
}

/// Drops the XData BuilderSpec block (and its doc line): it is the builder's own bookkeeping.
ClassMethod WithoutSpec(pText As %String) As %String [ Internal ]
{
	Set tOut = "", tSkip = 0, tN = $LENGTH(pText, $CHAR(10))
	For i = 1:1:tN {
		Set tLine = $PIECE(pText, $CHAR(10), i)
		// The doc line above the block belongs to it
		Continue:('tSkip && (tLine [ "/// Workbench form values;"))
		If 'tSkip && (tLine [ "XData BuilderSpec") {
			Set tSkip = 1
			Continue
		}
		If tSkip {
			// The XData body is { json }; its closing brace is the first line that is exactly }
			Set:(tLine = "}") tSkip = 0
			Continue
		}
		Set tOut = tOut_tLine_$SELECT(i < tN: $CHAR(10), 1: "")
	}
	Quit tOut
}

}
