/// gen_ai_client_* metrics (OpenTelemetry GenAI semantic-convention names) for
/// /api/monitor/metrics. Replays are left out: they repeat a recorded run's tokens and time.
Class AgenticProd.Monitor.GenAI Extends AgenticProd.Monitor.Metrics
{

Parameter PRODUCT = "gen_ai";

Method GetSensors() As %Status
{
	Set tSC = $$$OK
	Try {
		Do ..SetSensorInfo("client_token_usage", "Tokens used by the triage agent, by model and token type", "counter")
		Set tRS = ..Query("SELECT %EXACT(Model) AS Model, SUM(PromptTokens) - SUM(CacheReadTokens) AS InputTokens, SUM(CacheReadTokens) AS CachedInputTokens, SUM(CompletionTokens) - SUM(ReasoningTokens) AS OutputTokens, SUM(ReasoningTokens) AS ReasoningOut"
			_" FROM AgenticProd_Data.Usage WHERE (Replay = 0 OR Replay IS NULL) AND Model IS NOT NULL GROUP BY %EXACT(Model)")
		While tRS.%Next() {
			For tType = "input", "cached_input", "output", "reasoning" {
				Kill tLabels
				Set tLabels("model") = tRS.Model, tLabels("type") = tType
				Do ..SetSensorLabels("client_token_usage", +$CASE(tType, "input": tRS.InputTokens, "cached_input": tRS.CachedInputTokens, "output": tRS.OutputTokens, : tRS.ReasoningOut), .tLabels)
			}
		}

		// Prometheus summary: quantile series plus _sum and _count
		Do ..SetSensorInfo("client_operation_duration_seconds", "Agent run duration in seconds, by model", "summary", "seconds")
		Set tRS = ..Query("SELECT Model, TotalMs FROM AgenticProd_Data.Usage WHERE (Replay = 0 OR Replay IS NULL) AND Model IS NOT NULL AND TotalMs IS NOT NULL")
		While tRS.%Next() {
			Set tM = tRS.Model, tN(tM) = $GET(tN(tM)) + 1, tSum(tM) = $GET(tSum(tM)) + (tRS.TotalMs / 1000)
			Set tSorted(tM, tRS.TotalMs / 1000, tN(tM)) = ""
		}
		Set tM = ""
		For {
			Set tM = $ORDER(tN(tM))
			Quit:tM=""
			Kill tOne
			Merge tOne = tSorted(tM)
			For tQ = .5, .95 {
				Kill tLabels
				Set tLabels("model") = tM, tLabels("quantile") = "0"_tQ
				Do ..SetSensorLabels("client_operation_duration_seconds", +##class(AgenticProd.Eval.Runner).Percentile(.tOne, tN(tM), tQ), .tLabels)
			}
			Kill tLabels
			Set tLabels("model") = tM
			Do ..SetSensorLabels("client_operation_duration_seconds_sum", $NORMALIZE(tSum(tM), 3), .tLabels)
			Do ..SetSensorLabels("client_operation_duration_seconds_count", tN(tM), .tLabels)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
