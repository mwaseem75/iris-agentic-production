/// Recorded agent runs that ship with the repo (eval/recordings/recordings.json), so replay and the
/// sample cases work on a fresh install with no API key. Export writes the file from a finished live
/// eval run; Load, called by Setup, puts it back into an empty install. Synthetic data only.
Class AgenticProd.Recordings
{

Parameter RUNPROPS = "Label,Model,Mode,Cases,Status,Note,StartedAt,FinishedAt,CaseCount,Accuracy,ExactAccuracy,FinalAccuracy,FinalExactAccuracy,ClassAccuracy,MappingAccuracy,UnsafeAgent,UnsafeFinal,TimedOut,TotalTokens,TotalCostUsd,CostPerMessageUsd,P50Seconds,P95Seconds";

Parameter RESULTPROPS = "CaseId,Slug,CaseGroup,NoTriage,ExpectedDecision,AgentDecision,FinalDecision,FinalOutcome,ExpectedClass,AgentClass,ClassMatch,ExpectedLoinc,AgentLoinc,LoincMatch,FixMatch,Acceptable,Exact,FinalAcceptable,FinalExact,UnsafeAgent,UnsafeFinal,Injection,InjectionFlagged,PromptTokens,CompletionTokens,ReasoningTokens,CostUsd,Seconds,CreatedAt";

/// Saved session IDs are left out: those sessions do not exist on another install.
Parameter USAGEPROPS = "Provider,Model,PromptTokens,CompletionTokens,ReasoningTokens,CacheReadTokens,CacheCreationTokens,Interactions,ToolCalls,LlmMs,ToolMs,TotalMs,CostUsd,Decision,Confidence,CaseId,DecisionJSON,PromptHash,AgentClass,CreatedAt";

ClassMethod File() As %String
{
	Quit ##class(AgenticProd.Paths).Dir("eval/recordings/recordings.json")
}

/// Write the latest finished live eval run with this label, its case results and its recorded agent
/// runs to pFile. Run it once after a live eval: do ##class(AgenticProd.Recordings).Export("v2 final")
ClassMethod Export(pLabel As %String, pFile As %String = {..File()}) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.EvalRun WHERE Label = ? AND Mode = 'live' AND Status = 'DONE' ORDER BY ID DESC", pLabel)
		If 'tRS.%Next() $$$ThrowStatus($$$ERROR($$$GeneralError, "no finished live eval run labelled '"_pLabel_"'"))
		Set tRunId = tRS.ID
		Set tOut = {"format": 1, "results": [], "usage": []}
		Set tOut.run = ..ToObject("AgenticProd.Data.EvalRun", tRunId, ..#RUNPROPS)

		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM AgenticProd_Data.EvalResult WHERE RunId = ? ORDER BY CaseId", tRunId)
		While tRS.%Next() {
			Do tOut.results.%Push(..ToObject("AgenticProd.Data.EvalResult", tRS.ID, ..#RESULTPROPS))
		}

		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM AgenticProd_Data.Usage WHERE EvalRunId = ? AND COALESCE(Replay, 0) = 0 AND DecisionJSON IS NOT NULL ORDER BY ID", tRunId)
		While tRS.%Next() {
			Do tOut.usage.%Push(..ToObject("AgenticProd.Data.Usage", tRS.ID, ..#USAGEPROPS))
		}

		Set tDir = ##class(%File).GetDirectory(pFile)
		If '##class(%File).DirectoryExists(tDir) Do ##class(%File).CreateDirectoryChain(tDir)
		Set tStream = ##class(%Stream.FileCharacter).%New()
		Set tStream.TranslateTable = "UTF8"
		$$$ThrowOnError(tStream.LinkToFile(pFile))
		Do tOut.%ToJSON(tStream)
		$$$ThrowOnError(tStream.%Save())
		Write "Exported run ", tRunId, ": ", tOut.results.%Size(), " results, ", tOut.usage.%Size(), " recorded runs to ", pFile, !
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Load the shipped recordings. Nothing happens when the file is missing or the same run (label and
/// start time) is already in the database, so Setup can call it on every install and update.
ClassMethod Load(pFile As %String = {..File()}) As %Status
{
	Set tSC = $$$OK
	Try {
		If '##class(%File).Exists(pFile) Quit
		Set tStream = ##class(%Stream.FileCharacter).%New()
		Set tStream.TranslateTable = "UTF8"
		$$$ThrowOnError(tStream.LinkToFile(pFile))
		Set tIn = {}.%FromJSON(tStream)

		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM AgenticProd_Data.EvalRun WHERE Label = ? AND StartedAt = ?", tIn.run.Label, tIn.run.StartedAt)
		If tRS.%Next() Quit

		Set tRun = ##class(AgenticProd.Data.EvalRun).%New()
		Do ..FromObject(tRun, tIn.run, ..#RUNPROPS)
		$$$ThrowOnError(tRun.%Save())
		Set tRunId = tRun.%Id()

		Set tIter = tIn.results.%GetIterator()
		While tIter.%GetNext(.tKey, .tVal) {
			Set tRow = ##class(AgenticProd.Data.EvalResult).%New()
			Do ..FromObject(tRow, tVal, ..#RESULTPROPS)
			Set tRow.RunId = tRunId
			$$$ThrowOnError(tRow.%Save())
		}
		Set tIter = tIn.usage.%GetIterator()
		While tIter.%GetNext(.tKey, .tVal) {
			Set tRow = ##class(AgenticProd.Data.Usage).%New()
			Do ..FromObject(tRow, tVal, ..#USAGEPROPS)
			Set tRow.EvalRunId = tRunId
			$$$ThrowOnError(tRow.%Save())
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

ClassMethod ToObject(pClass As %String, pId As %String, pProps As %String) As %DynamicObject [ Private ]
{
	Set tRow = $CLASSMETHOD(pClass, "%OpenId", pId)
	Set tObj = {}
	For i = 1:1:$LENGTH(pProps, ",") {
		Set tName = $PIECE(pProps, ",", i)
		Do tObj.%Set(tName, $PROPERTY(tRow, tName))
	}
	Quit tObj
}

ClassMethod FromObject(pRow As %Persistent, pSource As %DynamicObject, pProps As %String) [ Private ]
{
	For i = 1:1:$LENGTH(pProps, ",") {
		Set tName = $PIECE(pProps, ",", i)
		Set $PROPERTY(pRow, tName) = pSource.%Get(tName)
	}
}

}
