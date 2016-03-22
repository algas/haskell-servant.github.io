---
title: A web API as a type
toc: true
---

この章のソースは literate haskell file です。
まずいくつかの言語拡張と import を導入します。

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeOperators #-}
>
> module ApiType where
>
> import Data.Text
> import Servant.API

Consider the following informal specification of an API:

以下のように大雑把にAPIの仕様を考えてみましょう。

 > `/users` というエンドポイントは `age` や `name` などの値を持つ `sortby`
 > クエリ文字列を受け取り、`age`, `name`, `email`, `registration_date` といった
 > ユーザ情報を持つJSONオブジェクトの一覧を返します。

これを形式化してみましょう。形式化されたAPIからウェブアプリを書くための多くの手段を得られます。
他にもクライアントライブラリやドキュメントを書く手段にもなります。

それでは sevant を使ってどのようにAPIを記述すれば良いのでしょうか？
前述のとおりエンドポイントを書くには古き良き Haskell の **型** を使います。

> type UserAPI = "users" :> QueryParam "sortby" SortBy :> Get '[JSON] [User]
>
> data SortBy = Age | Name
>
> data User = User {
>   name :: String,
>   age :: Int
> }

上記を掘り下げてみましょう:

- `"users"` は `/users` でアクセスできるエンドポイントを表しています。
- `QueryParam "sortby" SortBy` は `sortby` クエリ文字列パラメータを持つ
エンドポイントであり、`SortBy` 型の値を持つことが期待されます。
`SortBy` は `data SortBy = Age | Name` のように定義されます。
- `Get '[JSON] [User]` は HTTP GET リクエストを通じてアクセスできる、
JSONとしてUserのリストを返すようなエンドポイントであることを示しています。
異なるフォーマットでデータを使えるようにする方法は後ほど登場します。それは
クライアントのリクエスト内でどの [Accept header](http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html)
を選ぶかで決まります。
- `:>` 演算子は様々な「結合子」を分離します。static path や URL capture など。
static path や URL capture の場合だけ、その順序に意味があります。
`"users" :> "list-all" :> Get '[JSON] [User]` は `/users/list-all` と同じで、
`"list-all" :> "users" :> Get '[JSON] [User]` とは異なります。
`:>` は `/` と等価な場合もありますが、必ずしもそうではないこともあります。

複数のエンドポイントを持つAPIを `:<|>` 結合子を使って記述できます。
以下に一例を示します：

> type UserAPI2 = "users" :> "list-all" :> Get '[JSON] [User]
>            :<|> "list-all" :> "users" :> Get '[JSON] [User]

*servant* は多数の（out-of-the-box?）結合子を取り扱えますが、必要なだけ自分で書かなければ
なりません。servant で扱えるすべての結合子の概要を以下にまとめました。

Combinators
===========

Static strings
--------------

これまでに見てきた通り、static path を記述するのに型レベル文字列を使用できます。
(ただし、`DataKinds` 言語拡張を導入する必要があります。)
URL を書くには文字列を `/` で句切れば良いのです。

> type UserAPI3 = "users" :> "list-all" :> "now" :> Get '[JSON] [User]
>               -- これでアクセスできるエンドポイントは以下のようになります:
>               -- /users/list-all/now

`Delete`, `Get`, `Patch`, `Post` and `Put`
------------------------------------------

これら5つの結合子は非常に似ていますが、HTTPメソッドが異なります。
以下のように定義されています。

``` haskell
data Delete (contentTypes :: [*]) a
data Get (contentTypes :: [*]) a
data Patch (contentTypes :: [*]) a
data Post (contentTypes :: [*]) a
data Put (contentTypes :: [*]) a
```

エンドポイントは(自作しないかぎり)上記の5つの結合子のうちの1つで終わります。
例: 

> type UserAPI4 = "users" :> Get '[JSON] [User]
>            :<|> "admins" :> Get '[JSON] [User]

`Capture`
---------

URLの一部であるURLキャプチャは変数で、その実際の値は取得されてからリクエストハンドラに渡されます。
多くのウェブフレームワークでは `/users/:userid` のように書かれ、`:` のついた `userid` が変数名
またはプレースホルダです。例えば、もし `userid` が1以上の整数の範囲に収まるの場合には、そのエンド
ポイントは `/users/1` とか `/users/143` とかになります。

Servant における `Capture` 結合子は変数名と型で表される(型レベル)文字列で、取得したい値の
型を示しています。

``` haskell
data Capture (s :: Symbol) a
-- s :: シンボル 's' は型レベル文字列
```

キャプチャに正規表現を使っているウェブフレームワークもあります。
Servant は [`FromText`](https://hackage.haskell.org/package/servant/docs/Servant-Common-Text.html#t:FromText)
クラスを使っていて、取得された値はそのインスタンスになっていなければなりません。

例:

> type UserAPI5 = "user" :> Capture "userid" Integer :> Get '[JSON] User
>                 -- 'GET /user/:userid' と等価
>                 -- ただし servant では "userid" が Integer であることを明示している
>
>            :<|> "user" :> Capture "userid" Integer :> Delete '[] ()
>                 -- 'DELETE /user/:userid' と等価

`QueryParam`, `QueryParams`, `QueryFlag`, `MatrixParam`, `MatrixParams` and `MatrixFlag`
----------------------------------------------------------------------------------------

`QueryParam`, `QueryParams` and `QueryFlag` are about query string
parameters, i.e., those parameters that come after the question mark
(`?`) in URLs, like `sortby` in `/users?sortby=age`, whose value is
set to `age`. `QueryParams` lets you specify that the query parameter
is actually a list of values, which can be specified using
`?param[]=value1&param[]=value2`. This represents a list of values
composed of `value1` and `value2`. `QueryFlag` lets you specify a
boolean-like query parameter where a client isn't forced to specify a
value. The absence or presence of the parameter's name in the query
string determines whether the parameter is considered to have the
value `True` or `False`. For instance, `/users?active` would list only
active users whereas `/users` would list them all.

Here are the corresponding data type declarations:

``` haskell
data QueryParam (sym :: Symbol) a
data QueryParams (sym :: Symbol) a
data QueryFlag (sym :: Symbol)
```

[Matrix parameters](http://www.w3.org/DesignIssues/MatrixURIs.html)
are similar to query string parameters, but they can appear anywhere
in the paths (click the link for more details). A URL with matrix
parameters in it looks like `/users;sortby=age`, as opposed to
`/users?sortby=age` with query string parameters. The big advantage is
that they are not necessarily at the end of the URL. You could have
`/users;active=true;registered_after=2005-01-01/locations` to get
geolocation data about users whom are still active and registered
after *January 1st, 2005*.

Corresponding data type declarations below.

``` haskell
data MatrixParam (sym :: Symbol) a
data MatrixParams (sym :: Symbol) a
data MatrixFlag (sym :: Symbol)
```

Examples:

> type UserAPI6 = "users" :> QueryParam "sortby" SortBy :> Get '[JSON] [User]
>                 -- equivalent to 'GET /users?sortby={age, name}'
>
>            :<|> "users" :> MatrixParam "sortby" SortBy :> Get '[JSON] [User]
>                 -- equivalent to 'GET /users;sortby={age, name}'

Again, your handlers don't have to deserialize these things (into, for example,
a `SortBy`). *servant* takes care of it.

`ReqBody`
---------

Each HTTP request can carry some additional data that the server can use in its
*body*, and this data can be encoded in any format -- as long as the server
understands it. This can be used for example for an endpoint for creating new
users: instead of passing each field of the user as a separate query string
parameter or something dirty like that, we can group all the data into a JSON
object. This has the advantage of supporting nested objects.

*servant*'s `ReqBody` combinator takes a list of content types in which the
data encoded in the request body can be represented and the type of that data.
And, as you might have guessed, you don't have to check the content-type
header, and do the deserialization yourself. We do it for you. And return `Bad
Request` or `Unsupported Content Type` as appropriate.

Here's the data type declaration for it:

``` haskell
data ReqBody (contentTypes :: [*]) a
```

Examples:

> type UserAPI7 = "users" :> ReqBody '[JSON] User :> Post '[JSON] User
>                 -- - equivalent to 'POST /users' with a JSON object
>                 --   describing a User in the request body
>                 -- - returns a User encoded in JSON
>
>            :<|> "users" :> Capture "userid" Integer
>                         :> ReqBody '[JSON] User
>                         :> Put '[JSON] User
>                 -- - equivalent to 'PUT /users/:userid' with a JSON
>                 --   object describing a User in the request body
>                 -- - returns a User encoded in JSON

Request `Header`s
-----------------

Request headers are used for various purposes, from caching to carrying
auth-related data. They consist of a header name and an associated value. An
example would be `Accept: application/json`.

The `Header` combinator in servant takes a type-level string for the header
name and the type to which we want to decode the header's value (from some
textual representation), as illustrated below:

``` haskell
data Header (sym :: Symbol) a
```

Here's an example where we declare that an endpoint makes use of the
`User-Agent` header which specifies the name of the software/library used by
the client to send the request.

> type UserAPI8 = "users" :> Header "User-Agent" Text :> Get '[JSON] [User]

Content types
-------------

So far, whenever we have used a combinator that carries a list of content
types, we've always specified `'[JSON]`. However, *servant* lets you use several
content types, and also lets you define your own content types.

Four content-types are provided out-of-the-box by the core *servant* package:
`JSON`, `PlainText`, `FormUrlEncoded` and `OctetStream`. If for some obscure
reason you wanted one of your endpoints to make your user data available under
those 4 formats, you would write the API type as below:

> type UserAPI9 = "users" :> Get '[JSON, PlainText, FormUrlEncoded, OctetStream] [User]

We also provide an HTML content-type, but since there's no single library
that everyone uses, we decided to release 2 packages, *servant-lucid* and
*servant-blaze*, to provide HTML encoding of your data.

We will further explain how these content types and your data types can play
together in the [section about serving an API](/tutorial/server.html).

Response `Headers`
------------------

Just like an HTTP request, the response generated by a webserver can carry
headers too. *servant* provides a `Headers` combinator that carries a list of
`Header` and can be used by simply wrapping the "return type" of an endpoint
with it.

``` haskell
data Headers (ls :: [*]) a
```

If you want to describe an endpoint that returns a "User-Count" header in each
response, you could write it as below:

> type UserAPI10 = "users" :> Get '[JSON] (Headers '[Header "User-Count" Integer] [User])

Interoperability with other WAI `Application`s: `Raw`
-----------------------------------------------------

Finally, we also include a combinator named `Raw` that can be used for two reasons:

- You want to serve static files from a given directory. In that case you can just say:

> type UserAPI11 = "users" :> Get '[JSON] [User]
>                  -- a /users endpoint
>
>             :<|> Raw
>                  -- requests to anything else than /users
>                  -- go here, where the server will try to
>                  -- find a file with the right name
>                  -- at the right path

- You more generally want to plug a [WAI `Application`](http://hackage.haskell.org/package/wai)
into your webservice. Static file serving is a specific example of that. The API type would look the
same as above though. (You can even combine *servant* with other web frameworks
this way!)

<div style="text-align: center;">
  <a href="/tutorial/server.html">Next page: Serving an API</a>
</div>
