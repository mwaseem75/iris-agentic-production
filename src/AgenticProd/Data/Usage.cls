/// Tokens, cost and latency for one agent run (one row per TriageRequest sent to the agent).
/// Token fields come from session.GetStats(), which covers the whole session; response.Usage
/// only covers the last LLM request. Never purged: feeds the dashboard and evals.
Class AgenticProd.Data.Usage Extends %Persistent
{

/// Ens.MessageHeader ID of the TriageRequest.
Property HeaderId As %Integer;

/// Namespace the row's header and session IDs belong to: they are only unique within it
/// (IRISAPP, or a plug-in namespace such as LEGACY that shares this table).
Property Namespace As %String(MAXLEN = 64) [ InitialExpression = {$NAMESPACE} ];

/// Production (Visual Trace) session ID.
Property SessionId As %Integer;

/// Saved %AI.Agent.Session ID, for replay.
Property AgentSessionId As %String(MAXLEN = 50);

Property Provider As %String(MAXLEN = 50);

Property Model As %String(MAXLEN = 100);

Property PromptTokens As %Integer;

/// Includes ReasoningTokens.
Property CompletionTokens As %Integer;

Property ReasoningTokens As %Integer;

Property CacheReadTokens As %Integer;

Property CacheCreationTokens As %Integer;

/// LLM requests in the session.
Property Interactions As %Integer;

Property ToolCalls As %Integer;

Property LlmMs As %Integer;

Property ToolMs As %Integer;

/// Wall clock for the whole operation call, including retries and saving.
Property TotalMs As %Integer;

Property ContextTokens As %Integer;

Property ModelContextSize As %Integer;

/// Empty when the model has no PriceTable row.
Property CostUsd As %Numeric(SCALE = 6);

Property Decision As %String(MAXLEN = 20);

Property Confidence As %Numeric(SCALE = 4);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

/// Eval run and case, from an "EV<runId>-<caseId>" control ID; empty for normal traffic.
Property EvalRunId As %Integer;

Property CaseId As %String(MAXLEN = 20);

/// The Decision the operation returned, as JSON. Replay mode answers from it.
Property DecisionJSON As %String(MAXLEN = "");

/// 1 = answered from a recorded run, no LLM call (tokens and cost 0).
Property Replay As %Boolean [ InitialExpression = 0 ];

/// Agent class of the run, so a hosted agent's DAILYBUDGET counts only its own spend.
Property AgentClass As %String(MAXLEN = 128);

/// Hash of the prompt version and the input the agent was given (Operation.Agent.PromptHash).
/// Empty on rows recorded before it existed.
Property PromptHash As %String(MAXLEN = 32);

/// Replay rows only: 1 when the recorded run had a different PromptHash than the message being replayed.
Property PromptMismatch As %Boolean [ InitialExpression = 0 ];

Index HeaderIdx On HeaderId;

Index EvalCaseIdx On (EvalRunId, CaseId);

Index CaseModelIdx On (CaseId, Model);

Index CreatedIdx On CreatedAt;

/// Build an unsaved row from a GetStats() object and price it from PriceTable.
/// A missing price row is not an error here: the run is still recorded and CostUsd stays empty.
ClassMethod FromStats(pStats As %DynamicObject, pProvider As %String, pModel As %String) As AgenticProd.Data.Usage
{
	Set tRow = ..%New()
	Set tRow.Provider = pProvider
	Set tRow.Model = pModel
	Set tRow.PromptTokens = +pStats."total_prompt_tokens"
	Set tRow.CompletionTokens = +pStats."total_completion_tokens"
	Set tRow.ReasoningTokens = +pStats."total_reasoning_tokens"
	Set tRow.CacheReadTokens = +pStats."total_cache_read_tokens"
	Set tRow.CacheCreationTokens = +pStats."total_cache_creation_tokens"
	Set tRow.Interactions = +pStats."total_interactions"
	Set tRow.ToolCalls = +pStats."total_tool_calls"
	Set tRow.LlmMs = +pStats."total_llm_duration_ms"
	Set tRow.ToolMs = +pStats."total_tool_duration_ms"
	Set tRow.ContextTokens = +pStats."current_context_tokens"
	Set tRow.ModelContextSize = +pStats."model_context_size"
	If $$$ISOK(##class(AgenticProd.Data.PriceTable).Cost(pModel, tRow.PromptTokens, tRow.CompletionTokens, tRow.CacheReadTokens, tRow.CacheCreationTokens, .tCost)) {
		Set tRow.CostUsd = tCost
	}
	Quit tRow
}

Storage Default
{
<Data name="UsageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>HeaderId</Value>
</Value>
<Value name="3">
<Value>SessionId</Value>
</Value>
<Value name="4">
<Value>AgentSessionId</Value>
</Value>
<Value name="5">
<Value>Provider</Value>
</Value>
<Value name="6">
<Value>Model</Value>
</Value>
<Value name="7">
<Value>PromptTokens</Value>
</Value>
<Value name="8">
<Value>CompletionTokens</Value>
</Value>
<Value name="9">
<Value>ReasoningTokens</Value>
</Value>
<Value name="10">
<Value>CacheReadTokens</Value>
</Value>
<Value name="11">
<Value>CacheCreationTokens</Value>
</Value>
<Value name="12">
<Value>Interactions</Value>
</Value>
<Value name="13">
<Value>ToolCalls</Value>
</Value>
<Value name="14">
<Value>LlmMs</Value>
</Value>
<Value name="15">
<Value>ToolMs</Value>
</Value>
<Value name="16">
<Value>TotalMs</Value>
</Value>
<Value name="17">
<Value>ContextTokens</Value>
</Value>
<Value name="18">
<Value>ModelContextSize</Value>
</Value>
<Value name="19">
<Value>CostUsd</Value>
</Value>
<Value name="20">
<Value>Decision</Value>
</Value>
<Value name="21">
<Value>Confidence</Value>
</Value>
<Value name="22">
<Value>CreatedAt</Value>
</Value>
<Value name="23">
<Value>EvalRunId</Value>
</Value>
<Value name="24">
<Value>CaseId</Value>
</Value>
<Value name="25">
<Value>DecisionJSON</Value>
</Value>
<Value name="26">
<Value>Replay</Value>
</Value>
<Value name="27">
<Value>Namespace</Value>
</Value>
<Value name="28">
<Value>AgentClass</Value>
</Value>
<Value name="29">
<Value>PromptHash</Value>
</Value>
<Value name="30">
<Value>PromptMismatch</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.UsageD</DataLocation>
<DefaultData>UsageDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.UsageD</IdLocation>
<IndexLocation>^AgenticProd.Data.UsageI</IndexLocation>
<StreamLocation>^AgenticProd.Data.UsageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
