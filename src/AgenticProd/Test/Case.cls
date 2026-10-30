/// Base of every AgenticProd test class: while one runs, and for a grace period after,
/// Operation.Agent refuses live LLM calls in every namespace (it escalates "LLM blocked: test
/// run"), so a test that pushes messages through a production can never spend credit.
Class AgenticProd.Test.Case Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String) As %Status
{
	Do ##class(AgenticProd.Operation.Agent).MarkTestRun(1)
	Quit ##super(initvalue)
}

Method %OnClose() As %Status
{
	Do ##class(AgenticProd.Operation.Agent).MarkTestRun(0)
	Quit $$$OK
}

}
