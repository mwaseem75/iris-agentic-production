/// Specimen label printer. The label is rendered in Embedded Python (stdlib only) and written
/// as a text file to LabelPath. An order without a specimen (OBR-15) cannot be labelled and fails.
Class Legacy.Operation.LabelPrinter Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Property LabelPath As %String(MAXLEN = 500) [ InitialExpression = {##class(AgenticProd.Paths).Dir("data/legacy/labels/")} ];

Parameter SETTINGS = "LabelPath:Basic";

Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.Response) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tFile = ..RenderLabel(pRequest.OutputToString(), ##class(%File).NormalizeDirectory(..LabelPath))
		$$$TRACE("label written: "_tFile)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// pMessage is the raw ER7 text. Returns the label file path; raises
/// ValueError when ORC-2/OBR-2 or OBR-15 is empty.
ClassMethod RenderLabel(pMessage As %String, pDir As %String) As %String [ Language = python ]
{
	import os, datetime

	segs = {}
	for line in pMessage.splitlines():
		if line:
			fields = line.split('|')
			segs.setdefault(fields[0], fields)

	def field(seg, n):
		f = segs.get(seg, [])
		# MSH-1 is the separator itself, so MSH fields sit one place left
		i = n - 1 if seg == 'MSH' else n
		return f[i] if i < len(f) else ''

	order = field('ORC', 2) or field('OBR', 2)
	specimen = field('OBR', 15).split('^')[0]
	if not order:
		raise ValueError('no placer order number in ORC-2 or OBR-2: label not printed')
	if not specimen:
		raise ValueError('no specimen in OBR-15 for order ' + order + ': label not printed')

	mrn = field('PID', 3).split('^')[0]
	test = field('OBR', 4).split('^')
	label = '\n'.join([
		'ORDER  ' + order,
		'MRN    ' + mrn,
		'TEST   ' + (test[1] if len(test) > 1 and test[1] else test[0]),
		'SPEC   ' + specimen,
		'PRINT  ' + datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
	])
	os.makedirs(pDir, exist_ok=True)
	path = os.path.join(pDir, 'label_' + order + '.txt')
	with open(path, 'w', encoding='utf-8') as f:
		f.write(label + '\n')
	return path
}

}
