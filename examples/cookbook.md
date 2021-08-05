# HTTP::Tiny by Example

As per [RFC7230 §3.3], HTTP::Tiny does no place any limitations on sending
a body with the request, regardless of the method used. As such, the
signature for all request methods is similar, and should be fairly
predictable:

For wrappers like `get` and `post`, the signature is as follows:

```
method ... (
    Str $url,
       :%headers,
       :$content,
       :&data-callback,
       :&trailer-callback,
) returns Hash
```

All of these methods internally call the `request` method, which takes a
`$method` as the first parameter, and then the same parameters as above:


```
method request (
    Str $method,
    Str $url,
       :%headers,
       :$content,
       :&data-callback,
       :&trailer-callback,
) returns Hash
```

Below are some common use cases, with example output as sent by httpbin.org.

## Common requests

### GET with query parameters

Set the query parameters as part of the URL.

```
use HTTP::Tiny;
say .<content>.decode with HTTP::Tiny.new.get: 'http://httpbin.org/get?foo=bar';
# OUTPUT:
# {
#   "args": {
#     "foo": "bar"
#   },
#   "headers": {
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "origin": "...",
#   "url": "http://httpbin.org/get?foo=bar"
# }
```

### POST with JSON payload

Pass the serialised JSON string as content and set the `Content-Type`
header appropriately.

```
use JSON::Fast;
use HTTP::Tiny;
say .<content>.decode with HTTP::Tiny.new.post: "http://httpbin.org/post",
    headers => {
        Content-Type => 'application/json'
    },
    content => to-json {
        foo => True,
    }
# OUTPUT:
# {
#   "args": {},
#   "data": "{\n  \"foo\": true\n}",
#   "files": {},
#   "form": {},
#   "headers": {
#     "Content-Length": "17",
#     "Content-Type": "application/json",
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "json": {
#     "foo": true
#   },
#   "origin": "...",
#   "url": "http://httpbin.org/post"
# }
```

### POST with multipart file upload

Pass a Hash as content with the value as a IO::Path. The headers will
be set automatically.

```
use HTTP::Tiny;
say .<content>.decode with HTTP::Tiny.new.post: "http://httpbin.org/post",
    content => {
        foo => 'path/to/file.ext'.IO,
    }
# OUTPUT:
# {
#   "args": {},
#   "data": "",
#   "files": {
#     "foo": "Hello World! \ud83c\udf0d\n"
#   },
#   "form": {},
#   "headers": {
#     "Content-Length": "222",
#     "Content-Type": "multipart/form-data; boundary=\"FEegMkVRyWYNPDozXIyAPVgleFEnpruHoKGKefgf\"
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "json": null,
#   "origin": "...",
#   "url": "http://httpbin.org/post"
# }
```

### POST with URL encoded form

Set `content` to a Hash with the form values. The request will be
URL-encoded if none of the values are IO::Path objects.

You can choose to send this as multipart anyway by setting the
`Content-Type` header to `multipart/form-data`.

```
use HTTP::Tiny;
say .<content>.decode with HTTP::Tiny.new.post: "http://httpbin.org/post",
    content => {
        foo => True,
        values => [ 123, 456, 789 ],
    }
# OUTPUT:
# {
#   "args": {},
#   "data": "",
#   "files": {},
#   "form": {
#     "foo": "True",
#     "values": [
#       "123",
#       "456",
#       "789"
#     ]
#   },
#   "headers": {
#     "Content-Length": "41",
#     "Content-Type": "application/x-www-form-urlencoded",
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "json": null,
#   "origin": "...",
#   "url": "http://httpbin.org/post"
# }
```

### PUT binary data

Set `content` to a Blob. By default, the `Content-Type` will be set
to `application/octet-stream`, but you can set this appropriately if
you know what the data is.

```
use HTTP::Tiny;
say .<content>.decode with HTTP::Tiny.new.put: "http://httpbin.org/anything",
    content => Blob.new( "🦋".encode );
# OUTPUT:
# {
#   "args": {},
#   "data": "\ud83e\udd8b",
#   "files": {},
#   "form": {},
#   "headers": {
#     "Content-Length": "4",
#     "Content-Type": "application/octet-stream",
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "json": null,
#   "method": "PUT",
#   "origin": "...",
#   "url": "http://httpbin.org/post"
# }
```

[RFc7230 §3.3]: https://tools.ietf.org/html/rfc7230#section-3.3
