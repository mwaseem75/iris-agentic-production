/// Seeds the legacy demo in its own namespace. Run in LEGACY; safe to run again.
Class Legacy.Setup
{

/// Folders the production reads and writes, under DATADIR.
Parameter FOLDERS = "in,archive,lab,labels,ehr";

ClassMethod Run() As %Status
{
	Set tSC = $$$OK
	Try {
		For tI = 1:1:$LENGTH(..#FOLDERS, ",") {
			Set tDir = ##class(AgenticProd.Paths).Dir("data/legacy/")_$PIECE(..#FOLDERS, ",", tI)_"/"
			If '##class(%File).DirectoryExists(tDir), '##class(%File).CreateDirectoryChain(tDir) {
				$$$ThrowStatus($$$ERROR($$$GeneralError, "cannot create "_tDir))
			}
		}
		$$$ThrowOnError(##class(AgenticProd.Paths).ApplyToProduction("Legacy.OrdersProduction"))
		$$$ThrowOnError(..SeedLabCodes())
		$$$ThrowOnError(##class(Ens.Director).SetAutoStart("Legacy.OrdersProduction"))
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Local code -> LOINC. HBA1C-L is left out on purpose: samples/04 fails on it.
ClassMethod SeedLabCodes() As %Status
{
	Set tSC = $$$OK
	Try {
		For tPair = $LB("GLU", "2345-7"), $LB("NA", "2951-2"), $LB("K", "2823-3"), $LB("CREA", "2160-0") {
			$$$ThrowOnError(##class(Ens.Util.LookupTable).%UpdateValue("LegacyLabCodes", $LIST(tPair, 1), $LIST(tPair, 2)))
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
