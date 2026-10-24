/// One eval case in one Eval.Runner run: expected vs agent vs what Triage did. Never purged.
/// Match columns are empty when the case has nothing to compare (no expected class, LOINC or fix).
Class AgenticProd.Data.EvalResult Extends %Persistent
{

Property RunId As %Integer [ Required ];

Property CaseId As %String(MAXLEN = 20) [ Required ];

Property Slug As %String(MAXLEN = 100);

/// normal, edge, adversarial, control.
Property CaseGroup As %String(MAXLEN = 30);

/// Case expects the message to pass without Triage.
Property NoTriage As %Boolean;

Property ExpectedDecision As %String(MAXLEN = 20);

/// What the agent proposed (first agent run for the case), before the action matrix.
Property AgentDecision As %String(MAXLEN = 20);

/// Decision and outcome of the last DecisionLog row for the case: what Triage acted on.
/// FinalOutcome TIMEOUT = no outcome within the case timeout.
Property FinalDecision As %String(MAXLEN = 20);

Property FinalOutcome As %String(MAXLEN = 30);

Property ExpectedClass As %String(MAXLEN = 30);

Property AgentClass As %String(MAXLEN = 30);

Property ClassMatch As %Boolean;

Property ExpectedLoinc As %String(MAXLEN = 20);

Property AgentLoinc As %String(MAXLEN = 20);

Property LoincMatch As %Boolean;

/// Same steps (path and to) as the expected fix.
Property FixMatch As %Boolean;

/// Agent decision in acceptable_decisions.
Property Acceptable As %Boolean;

Property Exact As %Boolean;

/// Agent decision in must_not.
Property UnsafeAgent As %Boolean;

/// Triage applied, resent or rejected on a must_not decision.
Property UnsafeFinal As %Boolean;

/// The case carries an injection attempt.
Property Injection As %Boolean;

/// InjectionGuard flagged it, or the agent named it in its evidence or reason.
Property InjectionFlagged As %Boolean;

Property PromptTokens As %Integer;

/// Includes ReasoningTokens.
Property CompletionTokens As %Integer;

Property ReasoningTokens As %Integer;

Property CostUsd As %Numeric(SCALE = 6);

/// Send to final Triage outcome; empty for no_triage cases.
Property Seconds As %Numeric(SCALE = 1);

Property AgentSessionId As %String(MAXLEN = 50);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Index RunIdx On (RunId, CaseId);

Storage Default
{
<Data name="EvalResultDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunId</Value>
</Value>
<Value name="3">
<Value>CaseId</Value>
</Value>
<Value name="4">
<Value>Slug</Value>
</Value>
<Value name="5">
<Value>CaseGroup</Value>
</Value>
<Value name="6">
<Value>NoTriage</Value>
</Value>
<Value name="7">
<Value>ExpectedDecision</Value>
</Value>
<Value name="8">
<Value>AgentDecision</Value>
</Value>
<Value name="9">
<Value>FinalDecision</Value>
</Value>
<Value name="10">
<Value>FinalOutcome</Value>
</Value>
<Value name="11">
<Value>ExpectedClass</Value>
</Value>
<Value name="12">
<Value>AgentClass</Value>
</Value>
<Value name="13">
<Value>ClassMatch</Value>
</Value>
<Value name="14">
<Value>ExpectedLoinc</Value>
</Value>
<Value name="15">
<Value>AgentLoinc</Value>
</Value>
<Value name="16">
<Value>LoincMatch</Value>
</Value>
<Value name="17">
<Value>FixMatch</Value>
</Value>
<Value name="18">
<Value>Acceptable</Value>
</Value>
<Value name="19">
<Value>Exact</Value>
</Value>
<Value name="20">
<Value>UnsafeAgent</Value>
</Value>
<Value name="21">
<Value>UnsafeFinal</Value>
</Value>
<Value name="22">
<Value>Injection</Value>
</Value>
<Value name="23">
<Value>InjectionFlagged</Value>
</Value>
<Value name="24">
<Value>PromptTokens</Value>
</Value>
<Value name="25">
<Value>CompletionTokens</Value>
</Value>
<Value name="26">
<Value>ReasoningTokens</Value>
</Value>
<Value name="27">
<Value>CostUsd</Value>
</Value>
<Value name="28">
<Value>Seconds</Value>
</Value>
<Value name="29">
<Value>AgentSessionId</Value>
</Value>
<Value name="30">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^AgenticProd.Data.EvalResultD</DataLocation>
<DefaultData>EvalResultDefaultData</DefaultData>
<IdLocation>^AgenticProd.Data.EvalResultD</IdLocation>
<IndexLocation>^AgenticProd.Data.EvalResultI</IndexLocation>
<StreamLocation>^AgenticProd.Data.EvalResultS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
