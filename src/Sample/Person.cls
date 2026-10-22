Class Sample.Person Extends %Persistent
{
    Property Name As %String;
    Property Age As %Integer;

    ClassMethod Populate() As %Status
    {
        Set person1 = ##class(Sample.Person).%New()
        Set person1.Name = "Alice"
        Set person1.Age = 30
        Do person1.%Save()

        Set person2 = ##class(Sample.Person).%New()
        Set person2.Name = "Bob"
        Set person2.Age = 25
        Do person2.%Save()

        Set person3 = ##class(Sample.Person).%New()
        Set person3.Name = "Charlie"
        Set person3.Age = 55
        Do person3.%Save()

        set person4 = ##class(Sample.Person).%New()
        set person4.Name = "David"
        set person4.Age = 40
        Do person4.%Save()

        set person5 = ##class(Sample.Person).%New()
        set person5.Name = "Eve"
        set person5.Age = 29
        Do person5.%Save()

        Quit $$$OK
    }
Storage Default
{
<Data name="PersonDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Age</Value>
</Value>
</Data>
<DataLocation>^Sample.PersonD</DataLocation>
<DefaultData>PersonDefaultData</DefaultData>
<IdLocation>^Sample.PersonD</IdLocation>
<IndexLocation>^Sample.PersonI</IndexLocation>
<StreamLocation>^Sample.PersonS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}

