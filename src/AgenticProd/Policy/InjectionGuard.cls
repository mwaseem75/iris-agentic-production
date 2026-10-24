/// Deterministic scan of untrusted free text for instructions aimed at the agent.
/// No model involved: a hit only stops AUTO_FIX and is shown to the reviewer, it never drops a message.
Class AgenticProd.Policy.InjectionGuard
{

/// Lower-case phrases, "|" separated. "</data>" and "</untrusted_data" try to close our data blocks.
Parameter PHRASES = "ignore previous|ignore all previous|ignore rules|ignore the rules|ignore your instructions|disregard previous|system note|system prompt|ai agent|new instruction|you are now|</data>|</untrusted_data|<untrusted_data";

/// Comma list of PHRASES found in pText (case-insensitive), "" if none.
ClassMethod Scan(pText As %String) As %String
{
	Set tText = $ZCONVERT(pText, "L"), tHits = ""
	Quit:tText="" ""
	For i = 1:1:$LENGTH(..#PHRASES, "|") {
		Set tPhrase = $PIECE(..#PHRASES, "|", i)
		Set:tText[tPhrase tHits = tHits_$SELECT(tHits '= "": ", ", 1: "")_tPhrase
	}
	Quit tHits
}

}
