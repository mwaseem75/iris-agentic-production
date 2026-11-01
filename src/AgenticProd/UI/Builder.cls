/// Workbench builders: form values in, generated class out. Four kinds: tool (SQL query ToolSet),
/// skill, policy (protect arguments) and agent. Classes are only ever written under MyAI.*, only for
/// an admin, and only after the generated code compiled as a throw-away class. No LLM.
Class AgenticProd.UI.Builder Extends %RegisteredObject
{

Parameter PACKAGE = "MyAI.";

Parameter KINDS = "tool,skill,policy,agent";

/// Scratch classes for Validate and the tests; the package is skipped by the Library.
Parameter TEMPPACKAGE = "AgenticProd.Test.WbTmp.";

Parameter TYPES = "%String,%Integer,%Numeric,%Boolean";

Parameter OPS = "equals,contains,starts with";

/// Words that never appear in a read-only query (checked outside string literals).
Parameter FORBIDDEN = "INSERT,UPDATE,DELETE,DROP,ALTER,CREATE,GRANT,REVOKE,CALL,EXEC,EXECUTE,MERGE,TRUNCATE,INTO,COMMIT,ROLLBACK,LOCK";

// ---- options -------------------------------------------------------------------------------

/// Choices for the forms: provider configs, toolsets, skills and policies in this namespace.
ClassMethod Options(pAdmin As %Boolean) As %DynamicObject
{
	Set tOut = {"canEdit":(''pAdmin), "providers":[], "toolsets":[], "skills":[], "authorization":[], "audit":[]}
	Try {
		Set tIter = ##class(AgenticProd.Settings.Store).Providers().%GetIterator()
		While tIter.%GetNext(, .tP) { Do tOut.providers.%Push({"name":(tP.name), "model":(tP.model)}) }
	} Catch {}
	Set tSkills = ##class(AgenticProd.UI.Workbench).AgentClassesOf("%AI.Agent.Skill"), tSkillSet = ","
	Set tIter = tSkills.%GetIterator()
	While tIter.%GetNext(, .tS) {
		Set tSkillSet = tSkillSet_tS.class_","
		Set tInfo = ##class(AgenticProd.UI.Workbench).SkillInfo(tS.class)
		Do tOut.skills.%Push({"class":(tS.class), "name":(tInfo.name), "tools":(tInfo.tools)})
	}
	Set tIter = ##class(AgenticProd.UI.Workbench).AgentClassesOf("%AI.ToolSet").%GetIterator()
	While tIter.%GetNext(, .tT) {
		Continue:(tSkillSet [ (","_tT.class_","))
		Set tInfo = ##class(AgenticProd.UI.Workbench).ToolSetInfo(tT.class)
		Do tOut.toolsets.%Push({"class":(tT.class), "name":(tT.name), "tools":(tInfo.tools)})
	}
	Set tIter = ##class(AgenticProd.UI.Workbench).AgentClassesOf("%AI.Policy.Authorization,%AI.Policy.Audit").%GetIterator()
	While tIter.%GetNext(, .tP) {
		Set tList = $PROPERTY(tOut, tP.kind)
		Do tList.%Push({"class":(tP.class), "name":(tP.name)})
	}
	Quit tOut
}

// ---- generate ------------------------------------------------------------------------------

/// {"class", "code", "spec", "errors":[]}. errors empty means the form is acceptable; compiling is
/// a separate step (Validate). pClassOverride swaps the class name for scratch compiles.
ClassMethod Generate(pKind As %String, pSpec As %DynamicObject, pClassOverride As %String = "") As %DynamicObject
{
	Set tOut = {"class":"", "code":"", "spec":"", "errors":[]}
	If '$IsObject(pSpec) || ((","_..#KINDS_",") '[ (","_pKind_",")) {
		Do tOut.errors.%Push("Unknown template.")
		Quit tOut
	}
	Set tSpec = $CLASSMETHOD($CLASSNAME(), "Clean"_pKind, pSpec)
	Set tOut.spec = tSpec
	Set tOut.class = tSpec.class
	Set tErrs = $CLASSMETHOD($CLASSNAME(), "Check"_pKind, tSpec)
	Set tIter = tErrs.%GetIterator()
	While tIter.%GetNext(, .tE) { Do tOut.errors.%Push(tE) }
	If tOut.errors.%Size() = 0 {
		Set tOut.code = $CLASSMETHOD($CLASSNAME(), "Code"_pKind, tSpec, $SELECT(pClassOverride '= "": pClassOverride, 1: tSpec.class))
	}
	Quit tOut
}

/// Trimmed string field, "" when missing or not a string.
ClassMethod Str(pObj As %DynamicObject, pKey As %String) As %String [ Internal ]
{
	Set tVal = pObj.%Get(pKey)
	Quit:$IsObject(tVal) ""
	Quit $ZSTRIP(tVal, "<>W")
}

/// List of trimmed non-empty strings from an array field or a comma list.
ClassMethod StrList(pObj As %DynamicObject, pKey As %String) As %DynamicArray [ Internal ]
{
	Set tOut = [], tVal = pObj.%Get(pKey)
	If $IsObject(tVal), tVal.%IsA("%Library.DynamicArray") {
		Set tIter = tVal.%GetIterator()
		While tIter.%GetNext(, .tItem) {
			Set tItem = $ZSTRIP($SELECT($IsObject(tItem): "", 1: tItem), "<>W")
			Do:tItem'="" tOut.%Push(tItem)
		}
	}
	Quit tOut
}

ClassMethod Rows(pObj As %DynamicObject, pKey As %String) As %DynamicArray [ Internal ]
{
	Set tVal = pObj.%Get(pKey)
	Quit $SELECT($IsObject(tVal) && tVal.%IsA("%Library.DynamicArray"): tVal, 1: [])
}

ClassMethod Join(pList As %DynamicArray) As %String [ Internal ]
{
	Set tOut = "", tIter = pList.%GetIterator()
	While tIter.%GetNext(, .tItem) { Set tOut = tOut_$SELECT(tOut="": "", 1: ",")_tItem }
	Quit tOut
}

ClassMethod Contains(pList As %DynamicArray, pItem As %String) As %Boolean [ Internal ]
{
	Set tIter = pList.%GetIterator()
	While tIter.%GetNext(, .tItem) { Return:tItem=pItem 1 }
	Quit 0
}

/// ObjectScript string literal.
ClassMethod Q(pText As %String) As %String [ Internal ]
{
	Quit """"_$REPLACE(pText, """", """""")_""""
}

/// One line, for attributes and doc comments.
ClassMethod OneLine(pText As %String) As %String [ Internal ]
{
	Quit $ZSTRIP($TRANSLATE(pText, $CHAR(13,10,9), "   "), "<>W")
}

/// Text for an XData body: a line that starts with } would end the block.
ClassMethod XDataSafe(pText As %String) As %String [ Internal ]
{
	Set tText = $TRANSLATE(pText, $CHAR(13)), tOut = ""
	For i = 1:1:$LENGTH(tText, $CHAR(10)) {
		Set tLine = $PIECE(tText, $CHAR(10), i)
		Set:($EXTRACT(tLine) = "}") tLine = " "_tLine
		Set tOut = tOut_$SELECT(i=1: "", 1: $CHAR(10))_tLine
	}
	Quit tOut
}

/// First sentence, for the class description the Library shows.
ClassMethod Summary(pText As %String) As %String [ Internal ]
{
	Quit ##class(AgenticProd.UI.Workbench).FirstLine(pText)
}

ClassMethod NameOk(pName As %String, pPattern As %String) As %Boolean [ Internal ]
{
	Quit $CASE(pPattern, "id": pName ?1A.(1AN,1"_"), "kebab": pName ?1A.(1AN,1"-"), :0) && ($LENGTH(pName) <= 60)
}

/// MyAI.<package>.<name>: at least two parts after the root, letters and digits only.
ClassMethod ClassProblem(pClass As %String) As %String [ Internal ]
{
	Quit:pClass="" "Class name is required."
	Quit:($EXTRACT(pClass, 1, $LENGTH(..#PACKAGE)) '= ..#PACKAGE) "Class name must start with "_..#PACKAGE
	Quit:($LENGTH(pClass) > 100) "Class name is too long."
	Set tParts = $LENGTH(pClass, "."), tBad = 0
	Quit:(tParts < 3) "Class name needs a package and a name, like "_..#PACKAGE_"Tools.Queue."
	For i = 2:1:tParts { Set:'($PIECE(pClass, ".", i) ?1A.AN) tBad = 1 }
	Quit:tBad "Class name parts are letters and digits, starting with a letter."
	Quit ""
}

// ---- tool (SQL query ToolSet) --------------------------------------------------------------

ClassMethod Cleantool(pSpec As %DynamicObject) As %DynamicObject [ Internal ]
{
	Set tSpec = {"kind":"tool", "class":(..Str(pSpec, "class")), "tool":(..Str(pSpec, "tool")), "description":(..Str(pSpec, "description")), "args":[], "sql":(..NormalSql(..Str(pSpec, "sql"))), "maxRows":(+pSpec.%Get("maxRows"))}
	Set tIter = ..Rows(pSpec, "args").%GetIterator()
	While tIter.%GetNext(, .tA) {
		Continue:'$IsObject(tA)
		Do tSpec.args.%Push({"name":(..Str(tA, "name")), "type":(..Str(tA, "type")), "required":(''tA.%Get("required"))})
	}
	Quit tSpec
}

/// Trim and drop one trailing semicolon.
ClassMethod NormalSql(pSql As %String) As %String [ Internal ]
{
	Set tSql = $ZSTRIP($TRANSLATE(pSql, $CHAR(13)), "<>W")
	Set:($EXTRACT(tSql, $LENGTH(tSql)) = ";") tSql = $ZSTRIP($EXTRACT(tSql, 1, $LENGTH(tSql) - 1), ">W")
	Quit tSql
}

ClassMethod Checktool(pSpec As %DynamicObject) As %DynamicArray [ Internal ]
{
	Set tErr = []
	Set tP = ..ClassProblem(pSpec.class)
	Do:tP'="" tErr.%Push(tP)
	Do:'..NameOk(pSpec.tool, "id") tErr.%Push("Tool name is letters, digits and underscore, starting with a letter.")
	Do:($LENGTH(pSpec.description) < 20) tErr.%Push("Description is what the AI reads to decide when to use the tool: write at least a sentence.")
	Do:((pSpec.maxRows < 1) || (pSpec.maxRows > 1000) || (pSpec.maxRows '= (pSpec.maxRows\1))) tErr.%Push("Max rows is a whole number from 1 to 1000.")
	Set tNames = ","
	Set tIter = pSpec.args.%GetIterator()
	While tIter.%GetNext(, .tA) {
		If '..NameOk(tA.name, "id") { Do tErr.%Push("Argument name '"_tA.name_"' is letters, digits and underscore, starting with a letter.") }
		ElseIf tNames [ (","_tA.name_",") { Do tErr.%Push("Argument "_tA.name_" is listed twice.") }
		If (","_..#TYPES_",") '[ (","_tA.type_",") Do tErr.%Push("Argument "_tA.name_": type must be one of "_..#TYPES_".")
		Set tNames = tNames_tA.name_","
	}
	Set tIter = ..SqlProblems(pSpec.sql, tNames).%GetIterator()
	While tIter.%GetNext(, .tE) { Do tErr.%Push(tE) }
	Quit tErr
}

/// One SELECT, no comments, no write keywords, every :name declared. pNames is ",a,b,".
ClassMethod SqlProblems(pSql As %String, pNames As %String) As %DynamicArray [ Internal ]
{
	Set tErr = []
	If pSql = "" Do tErr.%Push("SQL is required.")  Quit tErr
	Set tBare = "", tIn = 0
	For i = 1:1:$LENGTH(pSql) {
		Set c = $EXTRACT(pSql, i)
		If c = "'" { Set tIn = 'tIn, tBare = tBare_" " }
		ElseIf 'tIn { Set tBare = tBare_c }
	}
	If tIn Do tErr.%Push("A quoted string in the SQL is not closed.")  Quit tErr
	Set tUp = $ZCONVERT(tBare, "U")
	If '(tUp ?1"SELECT"1(1C,1" ").E) Do tErr.%Push("Only a single SELECT statement is allowed.")
	If (tBare [ ";") Do tErr.%Push("Only one statement is allowed: remove the semicolon.")
	If (tBare [ "--") || (tBare [ "/*") Do tErr.%Push("Comments are not allowed in the SQL.")
	If pSql [ "]]>" Do tErr.%Push("The SQL cannot contain ']]>'.")
	Set tWords = " "_$TRANSLATE(tUp, $CHAR(9,10,13)_"(),*=<>+-/|.", $JUSTIFY("", 15))_" "
	Set tBad = ""
	For i = 1:1:$LENGTH(..#FORBIDDEN, ",") {
		Set tW = $PIECE(..#FORBIDDEN, ",", i)
		Set:(tWords [ (" "_tW_" ")) tBad = tBad_$SELECT(tBad="": "", 1: ", ")_tW
	}
	Do:tBad'="" tErr.%Push("Not allowed in a read-only query: "_tBad_".")
	If tBare [ "?" Do tErr.%Push("Use :name for arguments, not ?.")
	// :name references must match a declared argument
	Set tPos = 0, tUsed = ","
	For {
		Set tPos = $FIND(tBare, ":", tPos)
		Quit:'tPos
		Set tName = ""
		For j = tPos:1:$LENGTH(tBare) {
			Set c = $EXTRACT(tBare, j)
			Quit:'((c ?1AN) || (c = "_"))
			Set tName = tName_c
		}
		Continue:tName=""
		Set tUsed = tUsed_tName_","
		Do:(pNames '[ (","_tName_",")) tErr.%Push("Argument :"_tName_" is used in the SQL but not listed under Arguments.")
	}
	For i = 2:1:$LENGTH(pNames, ",") - 1 {
		Set tN = $PIECE(pNames, ",", i)
		Do:(tUsed '[ (","_tN_",")) tErr.%Push("Argument "_tN_" is listed but not used in the SQL.")
	}
	Quit tErr
}

ClassMethod Codetool(pSpec As %DynamicObject, pClass As %String) As %String [ Internal ]
{
	Set nl = $CHAR(10), tArgs = ""
	Set tIter = pSpec.args.%GetIterator()
	While tIter.%GetNext(, .tA) {
		Set tArgs = tArgs_$SELECT(tArgs="": "", 1: ", ")_tA.name_" As "_tA.type
		Set:'tA.required tArgs = tArgs_" = "_$SELECT(tA.type="%String": "''", 1: "0")
	}
	Set tSql = "", tLines = $LENGTH(pSpec.sql, nl)
	For i = 1:1:tLines { Set tSql = tSql_"      "_$ZSTRIP($PIECE(pSpec.sql, nl, i), ">W")_nl }
	Set tDesc = $ZCONVERT(..OneLine(pSpec.description), "O", "XML")
	Set tCode = "/// "_..Summary(pSpec.description)_nl_"Class "_pClass_" Extends %AI.ToolSet"_nl_"{"_nl_nl
	Set tCode = tCode_"XData Definition [ MimeType = application/xml ]"_nl_"{"_nl
	Set tCode = tCode_"<ToolSet Name="""_$PIECE(pClass, ".", *)_""">"_nl
	Set tCode = tCode_"  <Query Name="""_pSpec.tool_""" Arguments="""_tArgs_""" MaxRows="""_pSpec.maxRows_""""_nl
	Set tCode = tCode_"         Description="""_tDesc_""">"_nl_"    <![CDATA["_nl_tSql_"    ]]>"_nl_"  </Query>"_nl_"</ToolSet>"_nl_"}"_nl_nl
	Quit tCode_..SpecBlock(pSpec)_"}"_nl
}

/// The form values travel with the class so the Workbench can reopen it.
ClassMethod SpecBlock(pSpec As %DynamicObject) As %String [ Internal ]
{
	Set nl = $CHAR(10)
	Quit "/// Workbench form values; the builder reads this to reopen the class."_nl_"XData BuilderSpec [ MimeType = application/json ]"_nl_"{"_nl_pSpec.%ToJSON()_nl_"}"_nl_nl
}

// ---- skill ---------------------------------------------------------------------------------

ClassMethod Cleanskill(pSpec As %DynamicObject) As %DynamicObject [ Internal ]
{
	Quit {"kind":"skill", "class":(..Str(pSpec, "class")), "name":(..Str(pSpec, "name")), "description":(..OneLine(..Str(pSpec, "description"))), "instructions":($ZSTRIP($TRANSLATE(pSpec.%Get("instructions"), $CHAR(13)), "<>W")), "tools":(..StrList(pSpec, "tools"))}
}

ClassMethod Checkskill(pSpec As %DynamicObject) As %DynamicArray [ Internal ]
{
	Set tErr = []
	Set tP = ..ClassProblem(pSpec.class)
	Do:tP'="" tErr.%Push(tP)
	Do:'..NameOk(pSpec.name, "kebab") tErr.%Push("Skill name is letters, digits and hyphens, like code-mapping.")
	Do:($LENGTH(pSpec.description) < 20) tErr.%Push("Say when to load the skill: the AI reads this line to decide.")
	Do:($LENGTH(pSpec.instructions) < 20) tErr.%Push("Instructions are required.")
	Set tIter = pSpec.tools.%GetIterator()
	While tIter.%GetNext(, .tT) {
		Do:'..IsKind(tT, "%AI.ToolSet") tErr.%Push("Tools class "_tT_" is not a ToolSet in this namespace.")
	}
	Quit tErr
}

/// True when pClass exists and extends pBase.
ClassMethod IsKind(pClass As %String, pBase As %String) As %Boolean [ Internal ]
{
	Quit ''##class(%Dictionary.CompiledClass).%ExistsId(pClass) && ##class(AgenticProd.UI.Workbench).Extends(pClass, pBase)
}

ClassMethod Codeskill(pSpec As %DynamicObject, pClass As %String) As %String [ Internal ]
{
	Set nl = $CHAR(10)
	Set tCode = "/// "_..Summary(pSpec.description)_nl_"Class "_pClass_" Extends %AI.Agent.Skill"_nl_"{"_nl_nl
	Set tCode = tCode_"Parameter TOOLS = "_..Q(..Join(pSpec.tools))_";"_nl_nl
	Set tCode = tCode_"XData SUMMARY [ MimeType = text/yaml ]"_nl_"{"_nl_"name: "_pSpec.name_nl_"description: "_..Q(pSpec.description)_nl_"}"_nl_nl
	Set tCode = tCode_"XData INSTRUCTIONS [ MimeType = text/markdown ]"_nl_"{"_nl_..XDataSafe(pSpec.instructions)_nl_"}"_nl_nl
	Quit tCode_..SpecBlock(pSpec)_"}"_nl
}

// ---- policy (protect arguments) ------------------------------------------------------------

ClassMethod Cleanpolicy(pSpec As %DynamicObject) As %DynamicObject [ Internal ]
{
	Set tSpec = {"kind":"policy", "class":(..Str(pSpec, "class")), "tools":(..StrList(pSpec, "tools")), "rules":[], "message":(..OneLine(..Str(pSpec, "message")))}
	Set tIter = ..Rows(pSpec, "rules").%GetIterator()
	While tIter.%GetNext(, .tR) {
		Continue:'$IsObject(tR)
		Do tSpec.rules.%Push({"arg":(..Str(tR, "arg")), "op":(..Str(tR, "op")), "value":(..OneLine(..Str(tR, "value")))})
	}
	Quit tSpec
}

ClassMethod Checkpolicy(pSpec As %DynamicObject) As %DynamicArray [ Internal ]
{
	Set tErr = []
	Set tP = ..ClassProblem(pSpec.class)
	Do:tP'="" tErr.%Push(tP)
	Do:pSpec.message="" tErr.%Push("Write the message the agent gets when a call is denied.")
	Do:pSpec.rules.%Size()=0 tErr.%Push("Add at least one rule.")
	Set tIter = pSpec.tools.%GetIterator()
	While tIter.%GetNext(, .tT) { Do:'..NameOk(tT, "id") tErr.%Push("Tool name '"_tT_"' is not valid.") }
	Set tIter = pSpec.rules.%GetIterator()
	While tIter.%GetNext(, .tR) {
		Do:'..NameOk(tR.arg, "id") tErr.%Push("Rule argument '"_tR.arg_"' is not valid.")
		Do:((","_..#OPS_",") '[ (","_tR.op_",")) tErr.%Push("Rule for "_tR.arg_": choose equals, contains or starts with.")
		Do:tR.value="" tErr.%Push("Rule for "_tR.arg_": value is required.")
	}
	Quit tErr
}

ClassMethod Codepolicy(pSpec As %DynamicObject, pClass As %String) As %String [ Internal ]
{
	Set nl = $CHAR(10), tab = $CHAR(9)
	Set tToolCond = ""
	Set tIter = pSpec.tools.%GetIterator()
	While tIter.%GetNext(, .tT) { Set tToolCond = tToolCond_$SELECT(tToolCond="": "", 1: " || ")_"call.name = "_..Q(tT) }
	Set tCode = "Include %AI"_nl_nl_"/// Denies calls whose arguments match the rules; the read-only tiers still apply."_nl
	Set tCode = tCode_"Class "_pClass_" Extends AgenticProd.Policy.ReadOnly"_nl_"{"_nl_nl
	Set tCode = tCode_"Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status"_nl_"{"_nl
	Set tCode = tCode_tab_"Set tSC = ##super(toolref, call, metadata)"_nl_tab_"Quit:$$$ISERR(tSC) tSC"_nl
	Set tIter = pSpec.rules.%GetIterator()
	While tIter.%GetNext(, .tR) {
		Set tVal = ..Q($ZCONVERT(tR.value, "U")), tArg = "..ArgText(call, "_..Q(tR.arg)_")"
		Set tTest = $CASE(tR.op, "equals": tArg_" = "_tVal, "contains": tArg_" [ "_tVal, :"$EXTRACT("_tArg_", 1, "_$LENGTH(tR.value)_") = "_tVal)
		Set tCode = tCode_tab_"// "_tR.arg_": deny if "_tR.op_" "_..OneLine(tR.value)_nl
		Set tCode = tCode_tab_"If "_$SELECT(tToolCond="": "", 1: "("_tToolCond_") && ")_"("_tTest_") {"_nl
		Set tCode = tCode_tab_tab_"Quit $$$ERROR($$$AICoreToolAccessDenied, "_..Q(pSpec.message)_")"_nl_tab_"}"_nl
	}
	Set tCode = tCode_tab_"Quit $$$OK"_nl_"}"_nl_nl
	Set tCode = tCode_"/// Argument as upper-case text; objects and arrays compare as their JSON."_nl_"ClassMethod ArgText(call As %DynamicObject, name As %String) As %String"_nl_"{"_nl
	Set tCode = tCode_tab_"Set tVal = call.arguments.%Get(name)"_nl_tab_"Quit $ZCONVERT($SELECT($ISOBJECT(tVal): tVal.%ToJSON(), 1: tVal), ""U"")"_nl_"}"_nl_nl
	Quit tCode_..SpecBlock(pSpec)_"}"_nl
}

// ---- agent ---------------------------------------------------------------------------------

ClassMethod Cleanagent(pSpec As %DynamicObject) As %DynamicObject [ Internal ]
{
	Quit {"kind":"agent", "class":(..Str(pSpec, "class")), "providerConfig":(..Str(pSpec, "providerConfig")), "provider":(..Str(pSpec, "provider")), "apiKey":(..Str(pSpec, "apiKey")), "model":(..Str(pSpec, "model")), "toolsets":(..StrList(pSpec, "toolsets")), "skills":(..StrList(pSpec, "skills")), "authPolicy":(..Str(pSpec, "authPolicy")), "auditPolicy":(..Str(pSpec, "auditPolicy")), "maxSteps":(+pSpec.%Get("maxSteps")), "dailyBudget":(+pSpec.%Get("dailyBudget")), "instructions":($ZSTRIP($TRANSLATE(pSpec.%Get("instructions"), $CHAR(13)), "<>W"))}
}

ClassMethod Checkagent(pSpec As %DynamicObject) As %DynamicArray [ Internal ]
{
	Set tErr = []
	Set tP = ..ClassProblem(pSpec.class)
	Do:tP'="" tErr.%Push(tP)
	// No Config Store entry: the agent takes its provider and a key reference from the environment, like the triage agent
	If pSpec.providerConfig = "" {
		Do:'..NameOk(pSpec.provider, "id") tErr.%Push("Choose a model configuration (Settings tab) or a provider.")
		Do:'(pSpec.apiKey ?1"@{env:"1A.(1AN,1"_")1"}") tErr.%Push("The key is an environment reference like @{env:OPENAI_API_KEY}.")
	} ElseIf '..NameOk(pSpec.providerConfig, "id") {
		Do tErr.%Push("Choose a model configuration (Settings tab).")
	}
	Do:pSpec.model="" tErr.%Push("Model is required.")
	Do:($LENGTH(pSpec.instructions) < 20) tErr.%Push("Instructions are required.")
	Set tIter = pSpec.toolsets.%GetIterator()
	While tIter.%GetNext(, .tT) { Do:'..IsKind(tT, "%AI.ToolSet") tErr.%Push("Tools class "_tT_" is not a ToolSet in this namespace.") }
	Set tIter = pSpec.skills.%GetIterator()
	While tIter.%GetNext(, .tT) { Do:'..IsKind(tT, "%AI.Agent.Skill") tErr.%Push("Skill class "_tT_" is not a skill in this namespace.") }
	Do:((pSpec.maxSteps < 0) || (pSpec.maxSteps > 50) || (pSpec.maxSteps '= (pSpec.maxSteps\1))) tErr.%Push("Max steps is a whole number from 0 (no limit) to 50.")
	Do:((pSpec.dailyBudget < 0) || (pSpec.dailyBudget > 10000)) tErr.%Push("Daily budget is an amount in dollars, 0 for no limit.")
	Do:(pSpec.authPolicy'="")&&'..IsKind(pSpec.authPolicy, "%AI.Policy.Authorization") tErr.%Push("Authorization policy "_pSpec.authPolicy_" is not an authorization policy.")
	Do:(pSpec.auditPolicy'="")&&'..IsKind(pSpec.auditPolicy, "%AI.Policy.Audit") tErr.%Push("Audit policy "_pSpec.auditPolicy_" is not an audit policy.")
	Quit tErr
}

ClassMethod Codeagent(pSpec As %DynamicObject, pClass As %String) As %String [ Internal ]
{
	Set nl = $CHAR(10)
	Set tCode = "/// "_..Summary($PIECE($TRANSLATE(pSpec.instructions, "#"), nl, 1, 3))_nl_"Class "_pClass_" Extends AgenticProd.Agent.Base"_nl_"{"_nl_nl
	If pSpec.providerConfig '= "" {
		Set tCode = tCode_"Parameter PROVIDERCONFIG = "_..Q(pSpec.providerConfig)_";"_nl_nl
	} Else {
		Set tCode = tCode_"Parameter PROVIDER = "_..Q(pSpec.provider)_";"_nl_nl_"Parameter APIKEY = "_..Q(pSpec.apiKey)_";"_nl_nl
	}
	Set tCode = tCode_"Parameter MODEL = "_..Q(pSpec.model)_";"_nl_nl
	Set tCode = tCode_"Parameter TOOLSETS = "_..Q(..Join(pSpec.toolsets))_";"_nl_nl
	Set tCode = tCode_"Parameter SKILLS = "_..Q(..Join(pSpec.skills))_";"_nl_nl
	Set tCode = tCode_"// Attached in %OnInit by AgenticProd.Agent.Base when the caller sets no policy"_nl
	Set tCode = tCode_"Parameter AUTHPOLICY = "_..Q(pSpec.authPolicy)_";"_nl_nl
	Set tCode = tCode_"Parameter AUDITPOLICY = "_..Q(pSpec.auditPolicy)_";"_nl_nl
	// Read by Agent.Base: the step limit applies on every run; the daily budget when a production hosts the agent
	Set:pSpec.maxSteps tCode = tCode_"Parameter MAXSTEPS = "_pSpec.maxSteps_";"_nl_nl
	Set:pSpec.dailyBudget tCode = tCode_"Parameter DAILYBUDGET = "_pSpec.dailyBudget_";"_nl_nl
	Set tCode = tCode_"XData INSTRUCTIONS [ MimeType = text/markdown ]"_nl_"{"_nl_..XDataSafe(pSpec.instructions)_nl_"}"_nl_nl
	Quit tCode_..SpecBlock(pSpec)_"}"_nl
}

// ---- compile -------------------------------------------------------------------------------

/// Writes pCode as class pClass and compiles it. The class stays; callers delete scratch classes.
ClassMethod Compile(pClass As %String, pCode As %String) As %Status [ Internal ]
{
	Set tSC = $$$OK
	Try {
		Set nl = $CHAR(10)
		Set tCount = $LENGTH(pCode, nl) - 1
		For i = 1:1:tCount { Set tLines(i) = $PIECE(pCode, nl, i) }
		// Subscript 0 holds the line count
		Set tLines(0) = tCount
		$$$ThrowOnError(##class(%Compiler.UDL.TextServices).SetTextFromArray($NAMESPACE, pClass, .tLines))
		$$$ThrowOnError($SYSTEM.OBJ.Compile(pClass, "ck-d"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// {"ok", "errors":[], "code", "class"}. Compiles a scratch copy and deletes it: nothing is saved.
ClassMethod Validate(pKind As %String, pSpec As %DynamicObject) As %DynamicObject
{
	Set tOut = ..Generate(pKind, pSpec)
	Set tOut.ok = 0
	Quit:tOut.errors.%Size() tOut
	Set tTemp = ..TempName()
	Set tSC = ..CompileScratch(pKind, pSpec, tTemp)
	Do ..DropScratch(tTemp)
	If $$$ISERR(tSC) { Do ..AddStatus(tOut.errors, tSC) } Else { Set tOut.ok = 1 }
	Quit tOut
}

ClassMethod TempName() As %String [ Internal ]
{
	Quit ..#TEMPPACKAGE_"J"_$JOB_"x"_($INCREMENT(^||AgenticProd.Builder))
}

/// Generates pKind under the scratch name and compiles it.
ClassMethod CompileScratch(pKind As %String, pSpec As %DynamicObject, pTemp As %String) As %Status [ Internal ]
{
	Set tGen = ..Generate(pKind, pSpec, pTemp)
	Quit:tGen.errors.%Size() $$$ERROR($$$GeneralError, tGen.errors.%Get(0))
	Quit ..Compile(pTemp, tGen.code)
}

ClassMethod DropScratch(pTemp As %String) [ Internal ]
{
	Try { Do $SYSTEM.OBJ.Delete(pTemp, "-d") } Catch {}
}

ClassMethod AddStatus(pErrors As %DynamicArray, pSC As %Status) [ Internal ]
{
	Set tText = $SYSTEM.Status.GetErrorText(pSC)
	For i = 1:1:$LENGTH(tText, $CHAR(10)) {
		Set tLine = $ZSTRIP($PIECE(tText, $CHAR(10), i), "<>W")
		Do:tLine'="" pErrors.%Push(tLine)
	}
}

/// Validate, then write the real class. A class that exists but was not built here is never touched.
ClassMethod Save(pKind As %String, pSpec As %DynamicObject) As %DynamicObject
{
	Set tOut = ..Validate(pKind, pSpec)
	Set tOut.saved = 0
	Quit:'tOut.ok tOut
	Set tClass = tOut.class
	If ##class(%Dictionary.CompiledClass).%ExistsId(tClass) || ##class(%Dictionary.ClassDefinition).%ExistsId(tClass) {
		Set tOld = ..OpenSpec(tClass)
		If '$IsObject(tOld) || (tOld.kind '= pKind) {
			Set tOut.ok = 0
			Do tOut.errors.%Push("Class "_tClass_" already exists and was not built from this template.")
			Quit tOut
		}
	}
	Set tSC = ..Compile(tClass, tOut.code)
	If $$$ISERR(tSC) {
		Set tOut.ok = 0
		Do ..AddStatus(tOut.errors, tSC)
		Quit tOut
	}
	Set tOut.saved = 1
	Quit tOut
}

/// The saved form values of a MyAI class, or "" when it is not one the builders wrote.
ClassMethod OpenSpec(pClass As %String) As %DynamicObject
{
	Quit:..ClassProblem(pClass)'="" ""
	Set tText = ##class(AgenticProd.Settings.Store).XDataText(pClass, "BuilderSpec")
	Quit:tText="" ""
	Try { Set tSpec = {}.%FromJSON(tText) } Catch { Set tSpec = "" }
	Quit:'$IsObject(tSpec)||(tSpec.kind="") ""
	Quit tSpec
}

// ---- tests without AI ----------------------------------------------------------------------

/// Runs the tool with pArgs on a scratch copy: {"ok", "result", "elapsedMs", "errors":[]}.
/// Runs as the logged-in user; the agent itself runs as agentic_agent with SELECT only.
ClassMethod TestTool(pSpec As %DynamicObject, pArgs As %DynamicObject) As %DynamicObject
{
	Set tOut = ..Generate("tool", pSpec)
	Set tOut.ok = 0, tOut.result = ""
	Quit:tOut.errors.%Size() tOut
	Set tTemp = ..TempName()
	Try {
		$$$ThrowOnError(..CompileScratch("tool", pSpec, tTemp))
		Set tSet = $CLASSMETHOD(tTemp, "%New")
		Set tStart = $ZHOROLOG
		Set tResult = tSet.%Invoke(tOut.spec.tool, $SELECT($IsObject(pArgs): pArgs, 1: {}))
		Set tOut.elapsedMs = ($ZHOROLOG - tStart) * 1000 \ 1
		Set tOut.result = $SELECT($IsObject(tResult): tResult.%ToJSON(), 1: tResult)
		Set tOut.ok = 1
	} Catch ex {
		Do ..AddStatus(tOut.errors, ex.AsStatus())
	}
	Do ..DropScratch(tTemp)
	Quit tOut
}

/// Simulates a tool call against the policy: {"ok", "allowed", "message", "errors":[]}.
ClassMethod TestPolicy(pSpec As %DynamicObject, pTool As %String, pArgs As %DynamicObject) As %DynamicObject
{
	Set tOut = ..Generate("policy", pSpec)
	Set tOut.ok = 0, tOut.allowed = "", tOut.message = ""
	Quit:tOut.errors.%Size() tOut
	Set tTemp = ..TempName()
	Try {
		$$$ThrowOnError(..CompileScratch("policy", pSpec, tTemp))
		Set tPolicy = $CLASSMETHOD(tTemp, "%New")
		Set tCall = {"name":(pTool), "arguments":($SELECT($IsObject(pArgs): pArgs, 1: {}))}
		Set tSC = tPolicy.%CanExecute(pTool, tCall, {})
		Set tOut.allowed = ''$$$ISOK(tSC)
		Set:'tOut.allowed tOut.message = $SYSTEM.Status.GetOneStatusText(tSC)
		Set tOut.ok = 1
	} Catch ex {
		Do ..AddStatus(tOut.errors, ex.AsStatus())
	}
	Do ..DropScratch(tTemp)
	Quit tOut
}

// ---- REST entry ----------------------------------------------------------------------------

/// {"status":200|400|403, ...body}. pAction: generate, validate, save, test-tool, test-policy.
/// Everything except generate is refused unless pAdmin.
ClassMethod Handle(pAction As %String, pBody As %DynamicObject, pAdmin As %Boolean) As %DynamicObject
{
	If 'pAdmin Quit {"status":403, "error":"Builders are for administrators."}
	Set tKind = pBody.%Get("kind"), tSpec = pBody.%Get("spec")
	If '$IsObject(tSpec) Quit {"status":400, "error":"spec must be an object"}
	Set tArgs = pBody.%Get("args")
	Set tRes = ""
	If pAction = "generate" { Set tRes = ..Generate(tKind, tSpec) }
	ElseIf pAction = "validate" { Set tRes = ..Validate(tKind, tSpec) }
	ElseIf pAction = "save" { Set tRes = ..Save(tKind, tSpec) }
	ElseIf pAction = "test-tool" { Set tRes = ..TestTool(tSpec, tArgs) }
	ElseIf pAction = "test-policy" { Set tRes = ..TestPolicy(tSpec, pBody.%Get("tool"), tArgs) }
	If '$IsObject(tRes) Quit {"status":400, "error":"unknown action"}
	Do tRes.%Set("status", 200, "number")
	Quit tRes
}

}
