/// SAM metric classes: GetSensors runs clean, and /api/monitor/metrics serves the agentic and
/// gen_ai metrics. The HTTP test needs Setup.MonitorSetup to have run. No LLM.
Class AgenticProd.Test.Monitor.MetricsTest Extends AgenticProd.Test.Case
{

Method TestGetSensors()
{
	For tClass = "AgenticProd.Monitor.Metrics", "AgenticProd.Monitor.GenAI" {
		Do $$$AssertStatusOK($CLASSMETHOD(tClass, "%New").GetSensors(), tClass)
	}
}

Method TestPrometheusEndpoint()
{
	Set tReq = ##class(%Net.HttpRequest).%New()
	Set tReq.Server = "localhost", tReq.Port = 52773
	Do $$$AssertStatusOK(tReq.Get("/api/monitor/metrics"))
	Do $$$AssertEquals(tReq.HttpResponse.StatusCode, 200)
	Set tBody = ""
	While 'tReq.HttpResponse.Data.AtEnd {
		Set tBody = tBody_tReq.HttpResponse.Data.Read(32000)
	}
	For tName = "gen_ai_client_token_usage", "gen_ai_client_operation_duration_seconds", "agentic_decisions_total", "agentic_tool_calls_total",
		"agentic_unsafe_blocked_total", "agentic_llm_calls_saved_total", "agentic_approval_waiting" {
		Do $$$AssertTrue(tBody [ ("# TYPE "_tName_" "), tName_" served")
	}
}

}
