/// UI.Cost: forecast, cache savings and ROI arithmetic, and the summary built from stub rows.
Class AgenticProd.Test.UI.CostTest Extends AgenticProd.Test.Case
{

Parameter MODEL = "test-cost-model";

Parameter NS = "TESTCOST";

Method TestArithmetic()
{
	// 10 days in, $5 spent, 31-day month
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).Forecast(5, 10, 31), 15.5, "daily average x days in month")
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).Forecast(5, 0, 31), 0, "no day elapsed")
	// 2M cached tokens, input $0.15, cache read $0.075 per 1M
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).CacheSavings(2000000, .15, .075), .15, "cached tokens x rate difference")
	// 40 failures x 15 min = 10 h x $40
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).EngineerValue(40, 15, 40), 400)
	Do $$$AssertTrue(##class(AgenticProd.UI.Cost).RoiValueOK("15"), "number")
	Do $$$AssertTrue('##class(AgenticProd.UI.Cost).RoiValueOK("-1"), "negative refused")
	Do $$$AssertTrue('##class(AgenticProd.UI.Cost).RoiValueOK("abc"), "text refused")
}

Method TestDataFromStubRows()
{
	Do ..Cleanup()
	Do $$$AssertStatusOK(##class(AgenticProd.Data.PriceTable).AddIfMissing("test", ..#MODEL, 1, 2, .25, 0, 1, "unit test"))
	Set tBefore = ##class(AgenticProd.UI.Cost).Data(1, 30)
	Set tUsage = ##class(AgenticProd.Data.Usage).%New()
	Set tUsage.HeaderId = -9601, tUsage.Namespace = ..#NS, tUsage.Model = ..#MODEL, tUsage.Decision = "MAP_CODE"
	Set tUsage.CostUsd = .5, tUsage.CacheReadTokens = 1000000, tUsage.PromptTokens = 1000000, tUsage.EvalRunId = -9600
	Do $$$AssertStatusOK(tUsage.%Save())
	Set tLog = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLog.HeaderId = -9601, tLog.Namespace = ..#NS, tLog.Decision = "MAP_CODE", tLog.ErrorClass = "UNMAPPED_CODE", tLog.Outcome = "APPROVED", tLog.EvalRunId = -9600
	Do $$$AssertStatusOK(tLog.%Save())
	Set tLive1 = ##class(AgenticProd.Data.DecisionLog).%New()
	Set tLive1.HeaderId = -9602, tLive1.Namespace = ..#NS, tLive1.Decision = "AUTO_FIX", tLive1.ErrorClass = "BAD_FORMAT", tLive1.Outcome = "APPLIED"
	Do $$$AssertStatusOK(tLive1.%Save())

	Set tAfter = ##class(AgenticProd.UI.Cost).Data(1, 30)
	Do $$$AssertEquals($NORMALIZE(tAfter.cost.today - tBefore.cost.today, 6), .5, "today")
	Do $$$AssertEquals($NORMALIZE(tAfter.cost.month - tBefore.cost.month, 6), .5, "month")
	Do $$$AssertEquals($NORMALIZE(tAfter.savings.cacheUsd - tBefore.savings.cacheUsd, 6), .75, "1M cached x (1 - .25)")
	Do $$$AssertEquals(tAfter.roi.handled - tBefore.roi.handled, 1, "only the live APPLIED row counts, the eval APPROVED row does not")
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).Data(0, 30).roi.handled, tAfter.roi.handled, "ROI ignores the eval toggle")
	Do $$$AssertEquals($NORMALIZE(tAfter.roi.aiCost - tBefore.roi.aiCost, 6), 0, "eval cost is not in the ROI cost")
	Do $$$AssertEquals(tAfter.roi.engineerValue, ##class(AgenticProd.UI.Cost).EngineerValue(tAfter.roi.handled, tAfter.roi.minutesPerFailure, tAfter.roi.hourlyRate))
	Do $$$AssertEquals(tAfter.byDay.days.%Size(), 30)
	Do $$$AssertEquals(tAfter.byDay.series.%Get(..#MODEL).%Size(), 30, "one value per day")
	Do $$$AssertEquals(tAfter.byDay.series.%Get(..#MODEL).%Get(29), .5, "today is the last day")
	Do $$$AssertEquals(..Find(tAfter.byNamespace, ..#NS), .5, "by production")
	Do $$$AssertEquals(..Find(tAfter.byErrorClass, "UNMAPPED_CODE") - ..Find(tBefore.byErrorClass, "UNMAPPED_CODE"), .5, "by error class")
	Set tLive = ##class(AgenticProd.UI.Cost).Data(0, 30)
	Do $$$AssertEquals(..Find(tLive.byNamespace, ..#NS), 0, "eval rows out of live traffic")
	Do ..Cleanup()
}

Method TestRoiSettings()
{
	Set tMin = ##class(AgenticProd.UI.Cost).RoiSetting("MinutesPerFailure"), tRate = ##class(AgenticProd.UI.Cost).RoiSetting("EngineerHourlyRate")
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveItemSettings("budgets", {"MinutesPerFailure":20, "EngineerHourlyRate":55.5}))
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).RoiSetting("MinutesPerFailure"), 20)
	Do $$$AssertEquals(##class(AgenticProd.UI.Cost).RoiSetting("EngineerHourlyRate"), 55.5)
	Do $$$AssertTrue($$$ISERR(##class(AgenticProd.Settings.Store).SaveItemSettings("budgets", {"MinutesPerFailure":-5})), "negative refused")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM AgenticProd_Data.SettingsAudit WHERE Item = 'Cost' AND Field = 'MinutesPerFailure' AND NewValue = '20'")
	Do tRS.%Next()
	Do $$$AssertTrue(tRS.N >= 1, "change logged")
	Do $$$AssertStatusOK(##class(AgenticProd.Settings.Store).SaveItemSettings("budgets", {"MinutesPerFailure":(tMin), "EngineerHourlyRate":(tRate)}))
}

ClassMethod Find(pPairs As %DynamicArray, pName As %String) As %Numeric
{
	Set tIter = pPairs.%GetIterator()
	While tIter.%GetNext(, .tRow) {
		Quit:tRow.name=pName
	}
	Quit $SELECT($IsObject($GET(tRow))&&(tRow.name=pName): tRow.cost, 1: 0)
}

ClassMethod Cleanup()
{
	&sql(DELETE FROM AgenticProd_Data.Usage WHERE Namespace = 'TESTCOST')
	&sql(DELETE FROM AgenticProd_Data.DecisionLog WHERE Namespace = 'TESTCOST')
	Do ##class(AgenticProd.Data.PriceTable).ModelIdxDelete("test-cost-model")
}

}
