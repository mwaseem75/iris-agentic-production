/// EhrOut timeout matching on control IDs and eval case IDs. No production run.
Class AgenticProd.Test.Operation.EhrOutTest Extends AgenticProd.Test.Case
{

Method TestIsSimulated()
{
	Set tList = "MSG00015, 15"
	Do $$$AssertTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, "MSG00015"))
	Do $$$AssertTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, "EV7-15"), "eval send of case 15")
	Do $$$AssertNotTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, "EV7-05"))
	Do $$$AssertNotTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, "MSG000150"), "no partial match")
	Do $$$AssertNotTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, "15X"))
	Do $$$AssertNotTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated(tList, ""))
	Do $$$AssertNotTrue(##class(AgenticProd.Operation.EhrOut).IsSimulated("", "EV7-15"))
}

}
