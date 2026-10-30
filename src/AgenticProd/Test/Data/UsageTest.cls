/// Unit tests for AgenticProd.Data.Usage. Stub GetStats() output, no LLM.
Class AgenticProd.Test.Data.UsageTest Extends AgenticProd.Test.Case
{

Parameter TESTMODEL = "unittest-usage-model";

Method TestFromStats()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).AddIfMissing("test", ..#TESTMODEL, 1, 2, .1, 0, 1, "unit test"))

	// Field names as read from a live session in tracker 1.6.
	Set tStats = {"total_prompt_tokens":1000,"total_completion_tokens":500,"total_reasoning_tokens":300,
		"total_cache_read_tokens":400,"total_cache_creation_tokens":0,"total_interactions":2,
		"total_tool_calls":1,"total_llm_duration_ms":20500,"total_tool_duration_ms":12,
		"current_context_tokens":1500,"model_context_size":400000}
	Set tRow = ##class(AgenticProd.Data.Usage).FromStats(tStats, "test", ..#TESTMODEL)
	Do $$$AssertEquals(tRow.PromptTokens, 1000)
	Do $$$AssertEquals(tRow.CompletionTokens, 500)
	Do $$$AssertEquals(tRow.ReasoningTokens, 300)
	Do $$$AssertEquals(tRow.CacheReadTokens, 400)
	Do $$$AssertEquals(tRow.Interactions, 2)
	Do $$$AssertEquals(tRow.ToolCalls, 1)
	Do $$$AssertEquals(tRow.LlmMs, 20500)
	Do $$$AssertEquals(tRow.ModelContextSize, 400000)
	Do $$$AssertEquals(tRow.CostUsd, .00164, "priced from PriceTable")
	Set tRow.HeaderId = -1
	Do $$$AssertStatusOK(tRow.%Save(), "row saves")
	Do:tRow.%Id()'="" ##class(AgenticProd.Data.Usage).%DeleteId(tRow.%Id())

	Set tRow = ##class(AgenticProd.Data.Usage).FromStats(tStats, "test", "no-such-model")
	Do $$$AssertEquals(tRow.CostUsd, "", "unpriced model leaves cost empty")
	Do $$$AssertEquals(tRow.PromptTokens, 1000, "tokens still recorded")
}

Method OnAfterOneTest() As %Status
{
	Do ##class(AgenticProd.Data.PriceTable).ModelIdxDelete(..#TESTMODEL)
	Quit $$$OK
}

}
