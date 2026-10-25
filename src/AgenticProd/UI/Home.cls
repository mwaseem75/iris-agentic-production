/// Entry URL of the dashboard: /agenticprod/AgenticProd.UI.Home.cls.
/// A CSP page, not the static file, because only class pages get the IRIS login form; a static
/// file requested without a session returns 404. After login it sends the browser to the page.
Class AgenticProd.UI.Home Extends %CSP.Page
{

ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
	Set %response.Redirect = "dashboard.html"
	Quit 1
}

}
