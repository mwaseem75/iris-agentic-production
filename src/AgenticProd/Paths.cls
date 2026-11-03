/// Where the install keeps its files (kb/, eval/, web/, legacy/, data/). Docker mounts the repo at
/// DOCKERROOT; an IPM install without Docker copies them to <mgr>/agenticprod/ and Setup.Run records
/// that folder, or the one given as the module parameter root. Code reads the folder from here.
Class AgenticProd.Paths
{

Parameter DOCKERROOT = "/home/irisowner/dev/";

/// Shared with LEGACY (Data.* is mapped there).
Parameter CONFIG = "^AgenticProd.Data.Config";

/// Folder with a trailing slash. Without a recorded choice, the Docker mount.
ClassMethod Root() As %String
{
	Set tRoot = $GET(@..#CONFIG@("Root"), ..#DOCKERROOT)
	Quit tRoot_$SELECT($EXTRACT(tRoot, *) = "/": "", 1: "/")
}

/// Root plus a relative path, e.g. Dir("eval/cases/").
ClassMethod Dir(pRelative As %String) As %String
{
	Quit ..Root()_pRelative
}

/// Record the folder. pRoot "" keeps an earlier choice; with none, the Docker mount if it holds the
/// repo, else the folder IPM copied the files to. Creates the data folders.
ClassMethod Init(pRoot As %String = "") As %Status
{
	Set tSC = $$$OK
	Try {
		If pRoot '= "" {
			Set @..#CONFIG@("Root") = pRoot
		} ElseIf '$DATA(@..#CONFIG@("Root")), '##class(%File).DirectoryExists(..#DOCKERROOT_"kb/") {
			Set @..#CONFIG@("Root") = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_"agenticprod")
		}
		For tSub = "in", "out", "out-fhir", "rejected", "legacy/in", "legacy/archive", "legacy/lab", "legacy/labels", "legacy/ehr" {
			Set tDir = ..Dir("data/"_tSub_"/")
			// The image build mounts the repo read-only; the folders then come with the checkout (.gitkeep)
			// or are made on the first run. A folder that is missing is not an install error.
			If '##class(%File).DirectoryExists(tDir) Do ##class(%File).CreateDirectoryChain(tDir)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Parameter FHIRNOTE = "FHIR output: needs IRIS for Health";

/// 1 when this instance can build FHIR bundles (IRIS for Health). Plain IRIS has no HS.* classes,
/// so FhirOut, its validator and the FHIR tests are switched off there.
ClassMethod FhirAvailable() As %Boolean
{
	Quit ##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR")
		&& ##class(%Dictionary.CompiledClass).%ExistsId("HS.Gateway.HL7.HL7ToSDA3")
}

/// On plain IRIS: FhirOut disabled and LabRouter's FHIROutput off in production pProduction
/// (current namespace). No-op on IRIS for Health.
ClassMethod ApplyFhirAvailability(pProduction As %String) As %Status
{
	Quit:..FhirAvailable() $$$OK
	Set tSC = $$$OK
	Try {
		Set tProd = ##class(Ens.Config.Production).LoadFromClass(pProduction)
		If '$IsObject(tProd) $$$ThrowStatus($$$ERROR($$$GeneralError, "cannot open production "_pProduction))
		Set tChanged = 0
		For i = 1:1:tProd.Items.Count() {
			Set tItem = tProd.Items.GetAt(i)
			If tItem.ClassName = "AgenticProd.Operation.FhirOut", tItem.Enabled {
				Set tItem.Enabled = 0, tChanged = 1
			}
			Continue:(tItem.ClassName '= "AgenticProd.Process.LabRouter")
			For j = 1:1:tItem.Settings.Count() {
				Set tSetting = tItem.Settings.GetAt(j)
				If tSetting.Name = "FHIROutput", tSetting.Value '= 0 Set tSetting.Value = 0, tChanged = 1
			}
		}
		If tChanged {
			$$$ThrowOnError(tProd.%Save())
			$$$ThrowOnError(tProd.SaveToClass())
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Point the file paths of production pProduction (current namespace) at Root. The production
/// classes carry the Docker paths; this is a no-op when Root is the Docker mount.
ClassMethod ApplyToProduction(pProduction As %String) As %Status
{
	Quit:(..Root() = ..#DOCKERROOT) $$$OK
	Set tSC = $$$OK
	Try {
		Set tProd = ##class(Ens.Config.Production).LoadFromClass(pProduction)
		If '$IsObject(tProd) $$$ThrowStatus($$$ERROR($$$GeneralError, "cannot open production "_pProduction))
		Set tChanged = 0
		For i = 1:1:tProd.Items.Count() {
			Set tItem = tProd.Items.GetAt(i)
			For j = 1:1:tItem.Settings.Count() {
				Set tSetting = tItem.Settings.GetAt(j)
				If $EXTRACT(tSetting.Value, 1, $LENGTH(..#DOCKERROOT)) = ..#DOCKERROOT {
					Set tSetting.Value = ..Root()_$EXTRACT(tSetting.Value, $LENGTH(..#DOCKERROOT) + 1, *), tChanged = 1
				}
			}
		}
		If tChanged {
			$$$ThrowOnError(tProd.%Save())
			$$$ThrowOnError(tProd.SaveToClass())
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

}
