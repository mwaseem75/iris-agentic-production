/// Unit tests for AgenticProd.Data.DecisionLog. Stub decision text, no LLM.
Class AgenticProd.Test.Data.DecisionLogTest Extends %UnitTest.TestCase
{

Method TestRecord()
{
	Set tRequest = ##class(AgenticProd.Msg.TriageRequest).%New()
	Set tRequest.HeaderId = -1
	Set tRequest.SessionId = -1
	Set tRequest.Source = "unittest"
	Set tRequest.Format = "HL7v2"
	Set tRequest.ErrorText = "No mapping for local code GLU-01"
	Set tText = "{""decision"":""MAP_CODE"",""error_class"":""UNMAPPED_CODE"",""confidence"":0.81,"
		_"""mapping"":{""local_code"":""GLU-01"",""loinc"":""2345-7"",""display"":""Glucose""},"
		_"""validated"":false,""evidence"":[""lookup miss""],""reason"":""Local glucose code""}"
	Do $$$AssertStatusOK(##class(AgenticProd.Msg.Decision).FromAgentText(tText, .tDecision))
	Quit:'$IsObject(tDecision)
	Set tDecision.Model = "gpt-5-nano"
	Set tDecision.CostUsd = .0011

	Set tSC = ##class(AgenticProd.Data.DecisionLog).Record(tRequest, tDecision, .tId)
	Do $$$AssertStatusOK(tSC, "decision recorded")
	Set tRow = ##class(AgenticProd.Data.DecisionLog).%OpenId(tId)
	Do $$$AssertTrue($IsObject(tRow), "row exists")
	Quit:'$IsObject(tRow)
	Do $$$AssertEquals(tRow.HeaderId, -1)
	Do $$$AssertEquals(tRow.Decision, "MAP_CODE")
	Do $$$AssertEquals(tRow.LocalCode, "GLU-01")
	Do $$$AssertEquals(tRow.Loinc, "2345-7")
	Do $$$AssertEquals(tRow.ErrorText, "No mapping for local code GLU-01")
	Set tJSON = {}.%FromJSON(tRow.DecisionJSON)
	Do $$$AssertEquals(tJSON.evidence.%Get(0), "lookup miss", "full decision kept as JSON")
	Do $$$AssertEquals(tJSON.Model, "gpt-5-nano", "operation fields included")
	Do ##class(AgenticProd.Data.DecisionLog).%DeleteId(tId)
}

}
