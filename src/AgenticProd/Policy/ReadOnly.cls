Include %AI

/// Global authorization policy for the triage agent: the agent proposes, it never changes data.
/// Any tool marked REQUIRESAUTH (metadata.requires_auth) is hidden from the model and denied if called.
Class AgenticProd.Policy.ReadOnly Extends %AI.Policy.Authorization
{

Method %CanList(toolref As %String, metadata As %DynamicObject) As %Boolean
{
	Quit '..RequiresAuth(metadata)
}

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
	// Checked again here: %CanList only hides the tool, a model can still name it
	If ..RequiresAuth(metadata) {
		Quit $$$ERROR($$$AICoreToolAccessDenied, "Tool "_call.name_" can change data; the triage agent is read-only")
	}
	Quit $$$OK
}

/// Missing metadata counts as not requiring auth, matching AI Hub's default for plain tools.
ClassMethod RequiresAuth(metadata As %DynamicObject) As %Boolean
{
	Quit $IsObject(metadata) && ''metadata.%Get("requires_auth")
}

}
