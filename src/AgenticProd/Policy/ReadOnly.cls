Include %AI

/// Global authorization policy for the triage agent: the agent proposes, it never changes data.
/// Each tool has a tier, readonly, write or critical (Settings tab, item setting ToolTiers); only
/// tiers in EnabledTiers are listed to the model or run. A tool marked REQUIRESAUTH
/// (metadata.requires_auth) is at least write, whatever ToolTiers says.
Class AgenticProd.Policy.ReadOnly Extends %AI.Policy.Authorization
{

Parameter TIERS = "readonly,write,critical";

/// "tool=tier,..." for tools whose tier is set on the Settings tab; others are readonly.
Property ToolTiers As %String(MAXLEN = 2000);

/// Comma list of tiers the agent may use; readonly is always allowed.
Property EnabledTiers As %String(MAXLEN = 100) [ InitialExpression = "readonly" ];

Method %CanList(toolref As %String, metadata As %DynamicObject) As %Boolean
{
	// build 154: toolref is the tool name (get_segment, ...), as call.name is in %CanExecute
	Quit ..Enabled(..TierOf(toolref, metadata))
}

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
	// Checked again here: %CanList only hides the tool, a model can still name it
	Set tTier = ..TierOf(call.name, metadata)
	Quit:..Enabled(tTier) $$$OK
	Quit $$$ERROR($$$AICoreToolAccessDenied, "Tool "_call.name_" is tier "_tTier_"; the triage agent may only use "_..EnabledList())
}

/// The higher of the configured tier and what REQUIRESAUTH implies.
Method TierOf(pTool As %String, metadata As %DynamicObject) As %String
{
	Set tTier = "readonly"
	For i = 1:1:$LENGTH(..ToolTiers, ",") {
		Set tPair = $PIECE(..ToolTiers, ",", i)
		If $PIECE(tPair, "=") = pTool Set tTier = $PIECE(tPair, "=", 2) Quit
	}
	Set:..RequiresAuth(metadata)&&(tTier="readonly") tTier = "write"
	Quit tTier
}

Method Enabled(pTier As %String) As %Boolean
{
	Quit (pTier = "readonly") || $LISTFIND($LISTFROMSTRING(..EnabledTiers), pTier)
}

Method EnabledList() As %String
{
	Quit $SELECT(..EnabledTiers [ "readonly": ..EnabledTiers, 1: "readonly"_$SELECT(..EnabledTiers '= "": ","_..EnabledTiers, 1: ""))
}

/// Missing metadata counts as not requiring auth, matching AI Hub's default for plain tools.
ClassMethod RequiresAuth(metadata As %DynamicObject) As %Boolean
{
	Quit $IsObject(metadata) && ''metadata.%Get("requires_auth")
}

}
