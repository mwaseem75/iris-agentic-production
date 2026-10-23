/// Unit tests for AgenticProd.Data.PriceTable. Uses its own test model row, removed afterwards.
Class AgenticProd.Test.Data.PriceTableTest Extends %UnitTest.TestCase
{

Parameter TESTMODEL = "unittest-model";

Method TestCostAndSeed()
{
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).AddIfMissing("test", ..#TESTMODEL, 1, 2, .1, 0, 1, "unit test"))

	// 1000 prompt of which 400 cached: 600*1 + 500*2 + 400*0.1 = 1640 per 1M
	Set tSC = ##class(AgenticProd.Data.PriceTable).Cost(..#TESTMODEL, 1000, 500, 400, 0, .tCost)
	Do $$$AssertStatusOK(tSC, "cost for a priced model")
	Do $$$AssertEquals(tCost, .00164)

	Set tSC = ##class(AgenticProd.Data.PriceTable).Cost("no-such-model", 1000, 500, , , .tCost)
	Do $$$AssertStatusNotOK(tSC, "unpriced model is an error")
	Do $$$AssertEquals(tCost, "")

	// Seed twice: second run must not fail on the unique index or touch existing rows.
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).Seed())
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).Seed())
	Do $$$AssertTrue(##class(AgenticProd.Data.PriceTable).ModelIdxExists("gpt-5-nano"), "gpt-5-nano seeded")
	Do $$$AssertTrue(##class(AgenticProd.Data.PriceTable).ModelIdxExists("gpt-4o-mini"), "gpt-4o-mini seeded")
}

Method OnAfterOneTest() As %Status
{
	Do ##class(AgenticProd.Data.PriceTable).ModelIdxDelete(..#TESTMODEL)
	Quit $$$OK
}

}
