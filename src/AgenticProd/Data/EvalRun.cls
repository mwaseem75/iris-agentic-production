/// One Eval.Runner run and its summary metrics. Never purged: feeds the dashboard and 5.5.
/// Its ID is the run ID in the "EV<runId>-<caseId>" control IDs.
Class AgenticProd.Data.EvalRun Extends %Persistent
{

Property Label As %String(MAXLEN = 200);

Property Model As %String(MAXLEN = 100);

/// live or replay.
Property Mode As %String(MAXLEN = 10);

/// Case list as asked for ("all" or "01,05").
Property Cases As %String(MAXLEN = "");

/// RUNNING, DONE or ERROR.
Property Status As %String(MAXLEN = 20);

Property Note As %String(MAXLEN = "");

Property StartedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Property FinishedAt As %TimeStamp;

Property CaseCount As %Integer;

/// Share of cases whose agent decision is in acceptable_decisions (no_triage: no Triage happened).
Property Accuracy As %Numeric(SCALE = 4);

/// Share of cases whose agent decision equals the expected decision.
Property ExactAccuracy As %Numeric(SCALE = 4);

/// Over cases with an expected error_class.
Property ClassAccuracy As %Numeric(SCALE = 4);

/// Over cases with an expected LOINC.
Property MappingAccuracy As %Numeric(SCALE = 4);

/// Cases where the agent proposed a must_not decision.
Property UnsafeAgent As %Integer;

/// Cases where Triage carried out a must_not decision on its own. Target 0.
Property UnsafeFinal As %Integer;

Property TimedOut As %Integer;

Property TotalTokens As %Integer;

Property TotalCostUsd As %Numeric(SCALE = 6);

Property CostPerMessageUsd As %Numeric(SCALE = 6);

/// Send to final Triage outcome, cases that went to Triage only.
Property P50Seconds As %Numeric(SCALE = 1);

Property P95Seconds As %Numeric(SCALE = 1);

Storage Default
{
<Data name="EvalRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Label</Value>
</Value>
<Value name="3">
<Value>Model</Value>
</Value>
<Value name="4">
<Value>Mode</Value>
</Value>
<Value name="5">
<Value>Cases</Value>
</Value>
<Value name="6">
<Value>Status</Value>
</Value>
<Value name="7">
<Value>Note</Value>
</Value>
<Value name="8">
<Value>StartedAt</Value>
</Value>
<Value name="9">
<Value>FinishedAt</Value>
</Value>
<Value name="10">
<Value>CaseCount</Value>
</Value>
<Value name="11">
<Value>Accuracy</Value>
</Value>
<Value name="12">
<Value>ExactAccuracy</Value>
</Value>
<Value name="13">
<Value>ClassAccuracy</Value>
</Value>
<Value name="14">
<Value>MappingAccuracy</Value>
</Value>
<Value name="15">
<Value>UnsafeAgent</Value>
</Value>
<Value name="16">
<Value>UnsafeFinal</Value>
</Value>
<Value name="17">
<Value>TimedOut</Value>
</Value>
<Value name="18">
<Value>TotalTokens</Value>
</Value>
<Value name="19">
<Value>TotalCostUsd</Value>
</Value>
<Value name="20">
<Value>CostPerMessageUsd</Value>
</Value>
<Value name="21">
<Value>P50Seconds</Value>
</Value>
<Value name="22">
<Value>P95Seconds</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.EvalRunD</DataLocation>
<DefaultData>EvalRunDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.EvalRunD</IdLocation>
<IndexLocation>^AgenticProd.Data.EvalRunI</IndexLocation>
<StreamLocation>^AgenticProd.Data.EvalRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
