/// Numbers behind the dashboard's Cost tab. Reads Usage, DecisionLog, SavedCall and PriceTable only.
/// The arithmetic lives in small class methods so tests can check it without rows.
Class AgenticProd.UI.Cost Extends %RegisteredObject
{

Parameter DEFAULTDAYS = 30;

Parameter MAXDAYS = 90;

/// ROI assumptions, in the Settings tab's Budgets section. Kept in a global, not a production
/// item setting, so changing them does not restart the agent item.
Parameter ROIFIELDS = "MinutesPerFailure,EngineerHourlyRate";

Parameter CURRENCY = "USD";

/// Month-end estimate: the month's spend so far spread over the days elapsed (today counts as
/// a whole day), times the days in the month.
ClassMethod Forecast(pMonthToDate As %Numeric, pDayOfMonth As %Integer, pDaysInMonth As %Integer) As %Numeric
{
	Quit:pDayOfMonth<1 0
	Quit $NORMALIZE(pMonthToDate / pDayOfMonth * pDaysInMonth, 6)
}

/// USD saved by cached input tokens: they are billed at the cache-read rate instead of the input rate.
ClassMethod CacheSavings(pCachedTokens As %Integer, pInputPer1M As %Numeric, pCacheReadPer1M As %Numeric) As %Numeric
{
	Quit $NORMALIZE(pCachedTokens * (pInputPer1M - pCacheReadPer1M) / 1000000, 6)
}

/// Engineer time not spent: failures handled x minutes each x hourly rate.
ClassMethod EngineerValue(pHandled As %Integer, pMinutes As %Numeric, pHourlyRate As %Numeric) As %Numeric
{
	Quit $NORMALIZE(pHandled * pMinutes / 60 * pHourlyRate, 2)
}

ClassMethod RoiSetting(pField As %String) As %Numeric
{
	Quit:$DATA(^AgenticProd.Settings("roi", pField)) +^AgenticProd.Settings("roi", pField)
	Quit $CASE(pField, "MinutesPerFailure": 15, "EngineerHourlyRate": 40, : 0)
}

/// Value check for an ROI field: a non-negative number.
ClassMethod RoiValueOK(pValue As %String) As %Boolean
{
	Quit $ISVALIDNUM(pValue) && (pValue >= 0) && (pValue <= 1000000)
}

/// Cost Center JSON for the last pDays days (UTC). Live traffic only unless pIncludeEval;
/// replays repeat a recorded cost, so they are left out.
ClassMethod Data(pIncludeEval As %Boolean = 0, pDays As %Integer = {..#DEFAULTDAYS}) As %DynamicObject
{
	Set pDays = $SELECT(pDays<1: ..#DEFAULTDAYS, pDays>..#MAXDAYS: ..#MAXDAYS, 1: +pDays\1)
	Set tNow = $ZTIMESTAMP, tTodayH = +tNow
	Set tToday = $ZDATE(tTodayH, 3), tMonthStart = $EXTRACT(tToday, 1, 8)_"01"
	Set tWindowStart = $ZDATE(tTodayH - pDays + 1, 3)
	Set tFrom = $SELECT(tMonthStart]tWindowStart: tWindowStart, 1: tMonthStart)
	Set tYear = +$EXTRACT(tToday, 1, 4), tDayOfMonth = +$EXTRACT(tToday, 9, 10)
	Set tDaysInMonth = $CASE(+$EXTRACT(tToday, 6, 7), 2: $SELECT(((tYear#4=0)&&(tYear#100'=0))||(tYear#400=0): 29, 1: 28), 4: 30, 6: 30, 9: 30, 11: 30, : 31)
	Set tEvalWhere = $SELECT(pIncludeEval: "", 1: " AND u.EvalRunId IS NULL")

	// One pass over the usage rows feeds the day, production and error class breakdowns
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT u.CreatedAt, u.Model, u.Namespace, u.CostUsd, u.CacheReadTokens,"
		_" (SELECT MAX(d.ErrorClass) FROM AgenticProd_Data.DecisionLog d WHERE d.HeaderId = u.HeaderId AND d.Namespace = u.Namespace) AS ErrorClass"
		_" FROM AgenticProd_Data.Usage u WHERE u.CreatedAt >= ? AND (u.Replay = 0 OR u.Replay IS NULL)"_tEvalWhere, tFrom_" 00:00:00")
	If tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Set (tCostToday, tCostMonth, tCostWindow) = 0
	While tRS.%Next() {
		Set tDay = $EXTRACT(tRS.CreatedAt, 1, 10), tCost = +tRS.CostUsd
		Set:tDay=tToday tCostToday = tCostToday + tCost
		Set:'(tMonthStart]tDay) tCostMonth = tCostMonth + tCost
		Continue:tWindowStart]tDay
		Set tCostWindow = tCostWindow + tCost
		Set tByDay(tDay, tRS.Model) = $GET(tByDay(tDay, tRS.Model)) + tCost, tModels(tRS.Model) = ""
		Set tNs = $SELECT(tRS.Namespace'="": tRS.Namespace, 1: "(none)"), tByNs(tNs) = $GET(tByNs(tNs)) + tCost
		Set tEc = $SELECT(tRS.ErrorClass'="": tRS.ErrorClass, 1: "(none)"), tByEc(tEc) = $GET(tByEc(tEc)) + tCost
		Set tCached(tRS.Model) = $GET(tCached(tRS.Model)) + tRS.CacheReadTokens
	}

	// Cache savings: only models with a price row can be priced
	Set tCacheSaved = 0, tModel = ""
	For {
		Set tModel = $ORDER(tCached(tModel))
		Quit:tModel=""
		Set tPrice = ##class(AgenticProd.Data.PriceTable).ModelIdxOpen(tModel)
		Continue:'$IsObject(tPrice)
		Set tCacheSaved = tCacheSaved + ..CacheSavings(tCached(tModel), tPrice.InputPer1M, +tPrice.CacheReadPer1M)
	}

	// Failures handled in the window, and how many needed no engineer
	Set tLogWhere = $SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL")
	// Handled = nobody fixed the message by hand: applied, resent, rejected, or a mapping a reviewer approved
	Set tLog = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(DISTINCT HeaderId) AS Triaged,"
		_" SUM(CASE WHEN Outcome IN ('APPLIED','RESENT','REJECTED','APPROVED') THEN 1 ELSE 0 END) AS Handled"
		_" FROM AgenticProd_Data.DecisionLog WHERE CreatedAt >= ?"_tLogWhere, tWindowStart_" 00:00:00").%Get(0)

	// A learned mapping saves one average MAP_CODE run per message
	Set tSaved = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS N FROM AgenticProd_Data.SavedCall WHERE CreatedAt >= ?"_$SELECT(pIncludeEval: "", 1: " AND EvalRunId IS NULL"), tWindowStart_" 00:00:00").%Get(0)
	Set tRun = ##class(AgenticProd.UI.REST).Rows("SELECT COUNT(*) AS Runs, AVG(CostUsd) AS Cost FROM AgenticProd_Data.Usage WHERE Decision = 'MAP_CODE' AND (Replay = 0 OR Replay IS NULL)").%Get(0)

	Set tMinutes = ..RoiSetting("MinutesPerFailure"), tRate = ..RoiSetting("EngineerHourlyRate")
	Set tHandled = +tLog.Handled, tTriaged = +tLog.Triaged
	Set tValue = ..EngineerValue(tHandled, tMinutes, tRate)
	Set tItem = ##class(AgenticProd.Eval.Runner).#AGENTITEM
	Set tBudget = +##class(AgenticProd.UI.REST).AgentSetting(tItem, "DailyTokenBudget")
	Set tTokens = ##class(AgenticProd.Operation.Agent).TokensUsedToday()

	Set tOut = {"includeEval":(''pIncludeEval), "days":(pDays), "currency":(..#CURRENCY), "generatedAt":($ZDATETIME(tNow, 3))}
	Do tOut.%Set("includeEval", ''pIncludeEval, "boolean")
	Set tOut.cost = {"today":($NORMALIZE(tCostToday, 6)), "month":($NORMALIZE(tCostMonth, 6)), "window":($NORMALIZE(tCostWindow, 6)),
		"forecast":(..Forecast(tCostMonth, tDayOfMonth, tDaysInMonth)), "dayOfMonth":(tDayOfMonth), "daysInMonth":(tDaysInMonth)}
	Set tOut.failures = {"triaged":(tTriaged), "handled":(tHandled), "costPer":null}
	Do:tTriaged tOut.failures.%Set("costPer", $NORMALIZE(tCostWindow / tTriaged, 6), "number")
	Set tOut.budget = {"tokensToday":(tTokens), "dailyTokenBudget":(tBudget), "percent":null}
	Do:tBudget tOut.budget.%Set("percent", $NORMALIZE(tTokens / tBudget * 100, 1), "number")
	Set tOut.savings = {"cacheUsd":($NORMALIZE(tCacheSaved, 6)), "savedCalls":(+tSaved.N), "savedCallsUsd":null, "basedOnRuns":(+tRun.Runs)}
	Do:tRun.Runs tOut.savings.%Set("savedCallsUsd", $NORMALIZE(tSaved.N * tRun.Cost, 6), "number")
	Set tOut.roi = {"handled":(tHandled), "minutesPerFailure":(tMinutes), "hourlyRate":(tRate), "engineerValue":(tValue),
		"aiCost":($NORMALIZE(tCostWindow, 6)), "net":($NORMALIZE(tValue - tCostWindow, 2)), "hoursSaved":($NORMALIZE(tHandled * tMinutes / 60, 1))}

	// Chart series: one value per day and model, zero where a model had no cost
	Set tOut.byDay = {"days":[], "models":[], "series":{}}
	Set tModel = ""
	For {
		Set tModel = $ORDER(tModels(tModel))
		Quit:tModel=""
		Do tOut.byDay.models.%Push(tModel)
		Do tOut.byDay.series.%Set(tModel, [])
	}
	For i = pDays - 1:-1:0 {
		Set tDay = $ZDATE(tTodayH - i, 3)
		Do tOut.byDay.days.%Push(tDay)
		Set tModel = ""
		For {
			Set tModel = $ORDER(tModels(tModel))
			Quit:tModel=""
			Do tOut.byDay.series.%Get(tModel).%Push($NORMALIZE($GET(tByDay(tDay, tModel)), 6))
		}
	}
	Set tOut.byNamespace = ..Pairs(.tByNs)
	Set tOut.byErrorClass = ..Pairs(.tByEc)
	Quit tOut
}

/// [{name, cost}] from pBy(name) = cost, biggest first.
ClassMethod Pairs(ByRef pBy) As %DynamicArray [ Internal ]
{
	Set tName = ""
	For {
		Set tName = $ORDER(pBy(tName))
		Quit:tName=""
		Set tSort(-$NORMALIZE(pBy(tName), 6), tName) = ""
	}
	Set tOut = [], tKey = ""
	For {
		Set tKey = $ORDER(tSort(tKey))
		Quit:tKey=""
		Set tName = ""
		For {
			Set tName = $ORDER(tSort(tKey, tName))
			Quit:tName=""
			Do tOut.%Push({"name":(tName), "cost":(-tKey)})
		}
	}
	Quit tOut
}

}
