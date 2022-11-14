// This file contains your Data Connector logic
section Ozon;

[DataSource.Kind="Ozon", Publish="Ozon.Publish"]
shared Ozon.Data = Value.ReplaceType(Ozon.Func, FuncType);


FuncType = type function (
    client  as (type text meta [
        Documentation.FieldCaption = "ID клиента:",
        Documentation.SampleValues = {"54321"}
    ]),
    report as (type  text meta [
        Documentation.FieldCaption = "Тип отчёта:",
         Documentation.AllowedValues = { "Остатки", "Товары", "Продажи", "Возвраты"}
    ]),
    date1 as (type nullable text meta [
        Documentation.FieldCaption = "Дата начала:",
        Documentation.SampleValues = {"2022-02-28"}
    ]),
    date2 as (type nullable text meta [
        Documentation.FieldCaption = "Дата окончания:",
        Documentation.SampleValues = {"yesterday"}
    ])
     
    )
    as table meta [
        Documentation.Name = "Получение данных по OZON",
        Documentation.LongDescription =  "",
        Documentation.Examples = {
        [
            Description = "Получает 4 типа отчёта",
            Code = "ozon(""54321"",""t6nrej-ryte5-3nsbre-356erf"",""Остатки"", null, null)",
            Result = "Данные по OZON!"
        ]}
    ];



Ozon.Func =  (client as text, report as text, date1 as nullable text, date2 as nullable text)=>
let
    token = Extension.CurrentCredential()[Key],
    final = 
if report="Остатки" then stock(client,token) else 
if report="Товары" then products(client,token) else 
if report="Продажи" then sales(client,token,date1, date2) else 
if report="Возвраты" then returns(client,token) else "Неизвестный отчёт"
in final;


dateFunc=(dat)=>
       if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
       else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
       else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
       else Date.ToText(Date.From(dat),"yyyy-MM-dd");

getSales =  (month as text, client as text, token as text)=>
let 
    url = "https://api-seller.ozon.ru/v1/finance/realization",
    postData = Json.FromValue([date = month]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], ManualStatusHandling = {404,400}, Content=postData])),
    #"Преобразовано в таблицу" = Source[result][rows],
    #"Преобразовано в таблицу2" = Table.FromList(#"Преобразовано в таблицу", Splitter.SplitByNothing(), null, null, ExtraValues.Error)
in
    #"Преобразовано в таблицу2";
    
    
getNextToken = (client as text, token as text, last as text )=>
let 
    url = "https://api-seller.ozon.ru/v2/product/list",
    postData = Json.FromValue([limit = 1000, last_id = last, with= [attributes_data= true]]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData])),
    result = Source[result][last_id]
in
    result;
    
    
getProducts = (client as text, token as text, last as text)=>
let 
    url = "https://api-seller.ozon.ru/v2/product/list",
    postData = Json.FromValue([limit = 1000, last_id = last, with= [attributes_data= true]]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData])),
    result = Source[result],
    items = result[items]
in
    items;


dateTable = (date1,date2)=>
let
    Источник = List.Dates(date1, Number.From(date2-date1), #duration(1,0,0,0)),
    #"Преобразовано в таблицу" = Table.FromList(Источник, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Измененный тип" = Table.TransformColumnTypes(#"Преобразовано в таблицу",{{"Column1", type date}}),
    #"Добавлен пользовательский объект" = Table.AddColumn(#"Измененный тип", "Месяц", each Date.ToText([Column1], "yyyy-MM")),
    #"Измененный тип1" = Table.TransformColumnTypes(#"Добавлен пользовательский объект",{{"Месяц", type text}}),
    #"Удаленные дубликаты" = Table.Distinct(#"Измененный тип1", {"Месяц"}),
    #"Другие удаленные столбцы" = Table.SelectColumns(#"Удаленные дубликаты",{"Месяц"})
in
    #"Другие удаленные столбцы";
    
    
getOffer = (off_id as text, client as text, token as text) => 
let 
    url = "https://api-seller.ozon.ru/v2/product/info",
    postData = Json.FromValue( [offer_id = off_id]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json",  #"Client-Id"=client, #"Api-Key"=token], Content=postData]))
in
    Source;  

offsetList = (rows,limit)=> List.Accumulate({0..Number.RoundDown(rows/limit-0.0000000001)}, {}, (state, current)=>state&{current*limit} );


returns = (client as text, token as text)=>
let 
    url = "https://api-seller.ozon.ru/v2/returns/company/fbo",
    postData = Json.FromValue( [  limit = 10000,  offset= 0]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData])),
    count =  List.Accumulate({0..Number.RoundDown(Number.From(Source[count])/10000-0.0000000001)}, {}, (state, current)=>state&{current*10000} ),
    #"Преобразовано в таблицу" = Table.FromList(count, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Измененный тип" = Table.TransformColumnTypes(#"Преобразовано в таблицу",{{"Column1", type text}}),
    #"Добавлен пользовательский объект" = Table.AddColumn(#"Измененный тип", "data", each Json.Document(Web.Contents("https://api-seller.ozon.ru/v2/returns/company/fbo", [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=Json.FromValue( [limit = 10000, offset= [Column1]])]))[returns]),
    #"Другие удаленные столбцы" = Table.SelectColumns(#"Добавлен пользовательский объект",{"data"}),
    #"Развернутый элемент data" = Table.ExpandListColumn(#"Другие удаленные столбцы", "data")
in
    #"Развернутый элемент data";


sales = (client as text, token as text, date1 as nullable text, date2 as nullable text )=>
let
    date11 = if date1 = null then "2022-01-01" else dateFunc(date1),
    date22 = if date2 = null then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1), "yyyy-MM-dd") else dateFunc(date2),
    Источник = dateTable(Date.From(date11), Date.From(date22)),
    get = Table.AddColumn(Источник, "data", each try getSales([Месяц], client, token) otherwise null),
    exp = Table.ExpandTableColumn(get, "data", {"Column1"}, {"data"}),
    select = Table.SelectRows(exp, each ([data] <> null))
in
    select;


products = (client as text, token as text)=>
let 
    url = "https://api-seller.ozon.ru/v2/product/list",
    postData = Json.FromValue([limit = 1000, last_id = "", with= [attributes_data= true]]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData])),
    result = Source[result],
    tokenList = {""} & List.Generate(()=> result[last_id], each _ <> null and _ <> "", each getNextToken(client,token,_)),
    #"Преобразовано в таблицу" = Table.FromList(tokenList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Измененный тип" = Table.TransformColumnTypes(#"Преобразовано в таблицу",{{"Column1", type text}}),
    #"Добавлен пользовательский объект" = Table.AddColumn(#"Измененный тип", "data", each getProducts(client, token, [Column1])),
    #"Добавлен пользовательский объект1" = Table.AddColumn(#"Добавлен пользовательский объект", "length", each List.Count([data])),
    #"Строки с примененным фильтром" = Table.SelectRows(#"Добавлен пользовательский объект1", each [length] > 0),
    #"Другие удаленные столбцы" = Table.SelectColumns(#"Строки с примененным фильтром",{"data"}),
    #"Развернутый элемент data" = Table.ExpandListColumn(#"Другие удаленные столбцы", "data"),
    #"Развернутый" = Table.ExpandRecordColumn(#"Развернутый элемент data", "data", {"product_id", "offer_id", "is_fbo_visible", "is_fbs_visible", "archived", "is_discounted"}, {"product_id", "offer_id", "is_fbo_visible", "is_fbs_visible", "archived", "is_discounted"}),
    #"Измененный тип123" = Table.TransformColumnTypes(#"Развернутый",{{"offer_id", type text}}),
    #"added" = Table.AddColumn(#"Измененный тип123", "Пользовательский", each getOffer([offer_id], client, token)),
    #"Развернутый элемент Пользовательский" = Table.ExpandRecordColumn(#"added", "Пользовательский", {"result"}, {"result"})
in
    #"Развернутый элемент Пользовательский";

stock = (client as text, token as text)=>
let
offList = List.Generate(()=> 0, each _ >= 0, each if getStockLen(client,token,Text.From(_))>0 then _ + 100 else -1 ),
    #"Преобразовано в таблицу" = Table.FromList(offList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Измененный тип" = Table.TransformColumnTypes(#"Преобразовано в таблицу",{{"Column1", type text}}),
    #"Добавлен пользовательский объект" = Table.AddColumn(#"Измененный тип", "data", each Function.InvokeAfter(()=> getStock(client, token, [Column1]) , #duration(0,0,0,3)) ),
    #"Удаленные нижние строки" = Table.RemoveLastN(#"Добавлен пользовательский объект",1),
    #"Развернутый элемент data" = Table.ExpandListColumn(#"Удаленные нижние строки", "data"),
    #"Другие удаленные столбцы" = Table.SelectColumns(#"Развернутый элемент data",{"data"}),
    #"Развернутый элемент data1" = Table.ExpandRecordColumn(#"Другие удаленные столбцы", "data", {"offer_id", "sku", "title", "category", "discounted", "barcode", "length", "width", "height", "volume", "weight", "stock"}, {"offer_id", "sku", "title", "category", "discounted", "barcode", "length", "width", "height", "volume", "weight", "stock"})
in
    #"Другие удаленные столбцы";

getStockLen=(client as text, token as text, off as text)=>
let 
 
    url = "https://api-seller.ozon.ru/v1/analytics/stock_on_warehouses",
    postData = Json.FromValue([offset = off, limit = 100]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData, ManualStatusHandling = {404,400}] )),
    total_items = List.Count(Source[total_items])
in if off =-1 then 0 else total_items;


getStock=(client as text, token as text, off as text)=>
let 
 
    url = "https://api-seller.ozon.ru/v1/analytics/stock_on_warehouses",
    postData = Json.FromValue([offset = off, limit = 100]),
    Source = Json.Document(Web.Contents(url, [Headers=[#"Content-Type"="application/json", #"Client-Id"=client, #"Api-Key"=token], Content=postData, ManualStatusHandling = {404,400}] )),
    total_items = Source[total_items]
in if off =-1 then 0 else total_items;


Ozon = [
    TestConnection = (dataSourcePath) => 
        { "Ozon.Data", 
        Json.Document(dataSourcePath)[client], 
        Json.Document(dataSourcePath)[report],
        Json.Document(dataSourcePath)[date1], 
        Json.Document(dataSourcePath)[date2]
        },
    
    Authentication = [
        
         Key = []
   
    ],
    Label = "Ozon Connection"
];


Ozon.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { "Ozon Connector", "Ozon Help" },
    LearnMoreUrl = "",
    SourceImage = Ozon.Icons,
    SourceTypeImage = Ozon.Icons
];


Ozon.Icons = [
    Icon16 = { Extension.Contents("Ozon16.png"), Extension.Contents("Ozon20.png"), Extension.Contents("Ozon24.png"), Extension.Contents("Ozon32.png") },
    Icon32 = { Extension.Contents("Ozon32.png"), Extension.Contents("Ozon40.png"), Extension.Contents("Ozon48.png"), Extension.Contents("Ozon64.png") }
];