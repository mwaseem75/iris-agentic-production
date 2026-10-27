/// agentic_* metrics for /api/monitor/metrics (SAM, Prometheus text format); GenAI has the
/// gen_ai_* ones. Both registered by Setup.MonitorSetup for IRISAPP.
/// Counts are totals over the persistent Data tables, eval traffic included. SAM polls every
/// few seconds: keep this to a few grouped queries.
Class AgenticProd.Monitor.Metrics Extends %SYS.Monitor.SAM.Abstract
{

/// SAM names every metric PRODUCT_<sensor> and drops them when PRODUCT is empty, so one class
/// per prefix.
Parameter PRODUCT = "agentic";

Method GetSensors() As %Status
{
	Set tSC = $$$OK
	Try {
		Do ..SetSensorInfo("decisions_total", "Triage decisions by decision and outcome (DecisionLog)", "counter")
		Set tRS = ..Query("SELECT %EXACT(Decision) AS Decision, %EXACT(Outcome) AS Outcome, COUNT(*) AS N FROM AgenticProd_Data.DecisionLog GROUP BY %EXACT(Decision), %EXACT(Outcome)")
		While tRS.%Next() {
			Kill tLabels
			Set tLabels("decision") = tRS.Decision, tLabels("outcome") = tRS.Outcome
			Do ..SetSensorLabels("decisions_total", tRS.N, .tLabels)
		}

		Do ..SetSensorInfo("tool_calls_total", "Agent tool calls by tool, allowed or denied (ToolCall)", "counter")
		Set tRS = ..Query("SELECT %EXACT(Tool) AS Tool, COUNT(*) AS N FROM AgenticProd_Data.ToolCall GROUP BY %EXACT(Tool)")
		While tRS.%Next() {
			Kill tLabels
			Set tLabels("tool") = tRS.Tool
			Do ..SetSensorLabels("tool_calls_total", tRS.N, .tLabels)
		}

		Do ..SetSensorInfo("grounding_failures_total", "Agent decisions with a failed grounding check, by check (DecisionLog.GroundingFailed)", "counter")
		Set tRS = ..Query("SELECT GroundingFailed FROM AgenticProd_Data.DecisionLog WHERE Grounded = 0")
		While tRS.%Next() {
			For i = 1:1:$LENGTH(tRS.GroundingFailed, ",") Set tName = $PIECE(tRS.GroundingFailed, ",", i)  Set:tName'="" tFailed(tName) = $GET(tFailed(tName)) + 1
		}
		Set tName = ""
		For {
			Set tName = $ORDER(tFailed(tName), 1, tN)
			Quit:tName=""
			Kill tLabels
			Set tLabels("check") = tName
			Do ..SetSensorLabels("grounding_failures_total", tN, .tLabels)
		}

		Do ..SetSensorInfo("unsafe_blocked_total", "Agent proposals Triage refused to carry out and sent to a person (DOWNGRADED)", "counter")
		Do ..SetSensor("unsafe_blocked_total", ..Count("SELECT COUNT(*) AS N FROM AgenticProd_Data.DecisionLog WHERE Outcome %STARTSWITH 'DOWNGRADED:'"))
		Do ..SetSensorInfo("llm_calls_saved_total", "Messages that passed on a reviewer-approved mapping instead of an agent run", "counter")
		Do ..SetSensor("llm_calls_saved_total", ..Count("SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall"))
		Do ..SetSensorInfo("approval_waiting", "Approval tasks waiting for a reviewer", "gauge")
		Do ..SetSensor("approval_waiting", ..Count("SELECT COUNT(*) AS N FROM EnsLib_Workflow.TaskResponse r JOIN AgenticProd_Msg.ApprovalTask t ON t.ID = r.TaskStatus_Request WHERE r.TaskStatus_IsComplete = 0"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Method Query(pSQL As %String) As %SQL.StatementResult [ Internal ]
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, pSQL)
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Quit tRS
}

Method Count(pSQL As %String) As %Integer [ Internal ]
{
	Set tRS = ..Query(pSQL)
	Quit $SELECT(tRS.%Next(): +tRS.N, 1: 0)
}

}
