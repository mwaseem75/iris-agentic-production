Class Sample.Tools Extends %AI.Tool [dependsOn=Sample.Person]
{

/// Tool to add a person to the database
Method AddPerson(name As %String, age As %Integer) As %Status{
    Set person = ##class(Sample.Person).%New()
    Set person.Name = name
    Set person.Age = age
    Set sc =  person.%Save()
    Quit sc
}
/// Tool query database for people younger than a specified age
Query GetPeopleYoungerThan(age As %Integer) As %SQLQuery(
    ROWSPEC = "Name:%String,Age:%Integer") [ SqlProc ]
{
    SELECT Name, Age From Sample.Person Where Age < :age
}

}
