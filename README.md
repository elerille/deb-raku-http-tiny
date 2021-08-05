## NAME

HTTP::Tiny - A small, simple, correct HTTP/1.1 client

## SYNOPSIS

```raku
use HTTP::Tiny;

my $response = HTTP::Tiny.new.get: 'http://httpbin.org/get';

die "Failed!\n" unless $response<success>;

say "$response<status> $response<reason>";
# OUTPUT:
# 200 OK

for $response<headers>.kv -> $key, $v {
    for $v.List -> $value {
        say "$key: $value";
    }
}
# OUTPUT:
# content-type: application/json
# date: Fri, 09 Oct 2020 21:49:38 GMT
# connection: close
# content-length: 230
# server: gunicorn/19.9.0
# access-control-allow-origin: *
# access-control-allow-credentials: true

print $response<content>.decode if $response<content>;
# OUTPUT:
# {
#   "args": {},
#   "headers": {
#     "Host": "httpbin.org",
#     "User-Agent": "HTTP-Tiny",
#     "X-Amzn-Trace-Id": "..."
#   },
#   "origin": "...",
#   "url": "http://httpbin.org/get"
# }
```

## DESCRIPTION

This is a very simple but correct HTTP/1.1 client, designed for doing simple
requests without the overhead of a large framework like HTTP::UserAgent.

It is a Raku port of the Perl library of the same name. It supports
redirection, streaming requests and responses, multipart and URL-encoded
form uploads, and correctly handles multipart responses to ranged requests.

Cookie support is not yet implemented.

## METHODS

Calling the `new` method to construct an object is optional when using the
methods described in this section. When not doing so, `new` will be called
automatically before executing the request, and the created object will be
discarded after the request is complete.

### new

```raku
method new (
          :%default-headers,
    Set() :%no-proxy,
    Str   :$http-proxy,
    Str   :$https-proxy,
    Str   :$agent = 'HTTP-Tiny/VERSION Raku',
    Int   :$max-redirect = 5,
    Bool  :$keep-alive,
    Bool  :$throw-exceptions,
) returns HTTP::Tiny
```

Creates a new HTTP::Tiny object. The following attributes are parameters:

#### default-headers

A Hash of default headers to apply to requests. Headers specified during the
call take precedence over the ones specified here.

#### agent

A Str to use as the value of the `User-Agent` header. Defaults to
'HTTP-Tiny/$VERSION Raku'.

#### max-redirect

Maximum number of redirects allowed. Defaults to 5. Set to 0 to prevent
redirection.

#### keep-alive

Whether to re-use the last connection, if it is for the same scheme, host,
and port. Defaults to True.

#### throw-exceptions

When set to True, non-success HTTP responses will throw a `X::HTTP::Tiny`
exception. The original error response Hash will be available as the result of
the `.response` method of the exception.

#### proxy

URL of a generic proxy server for both HTTP and HTTPS connections.

Defaults to the value in the `all_proxy` or `ALL_PROXY` environment
variables (in that order). Set to the empty string to ignore variables set in
the environment.

#### no-proxy

Set of domain suffixes that should not be proxied. Any value that implements
the `Set` method is allowed. A Str is also allowed, in which case it must be
a comma-separated list of suffixes that will be split, trimmed, and coerced to
a Set.

Defaults to the value in the `no_proxy`, which will be treated like the Str
case described above.

#### http-proxy

URL of a proxy server for HTTP connections.

Defaults to the value in the `http_proxy` or `HTTP_PROXY` environment
variables, or to the value of the `proxy` parameter described above (in that
order). Set to the empty string to ignore variables set in the environment.

#### https-proxy

URL of a proxy server for HTTPS connections.

Defaults to the value in the `https_proxy` or `HTTPS_PROXY` environment
variables, or to the value of the `proxy` parameter described above (in that
order). Set to the empty string to ignore variables set in the environment.

### delete

Shorthand method for calling `request` with 'DELETE' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### get

Shorthand method for calling `request` with 'GET' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### head

Shorthand method for calling `request` with 'HEAD' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### options

Shorthand method for calling `request` with 'OPTIONS' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### patch

Shorthand method for calling `request` with 'PATCH' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### post

Shorthand method for calling `request` with 'POST' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### put

Shorthand method for calling `request` with 'PUT' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### trace

Shorthand method for calling `request` with 'TRACE' as the method. See the
documentation for `request` for full details on the supported parameters and
the return value.

### request

```raku
method request (
    Str $method,
    Str $url,
       :%headers,
       :$content,
       :&data-callback,
       :&trailer-callback,
) returns Hash
```

Executes an HTTP request of the given method type on the given URL. The URL
must have unsafe characters escaped and international domains encoded. Valid
HTTP methods are 'GET', 'DELETE', 'HEAD', 'OPTIONS', 'PATCH', 'POST', 'PUT',
and 'TRACE', with their names being case sensitive as per the HTTP/1.1
specification.

If the URL includes a "user:password" stanza, they will be used for
Basic-style authorisation headers. For example:

```raku
$ua.request: 'GET', 'http://Aladdin:open sesame@example.com/';
```

If the "user:password" stanza contains reserved characters, they must
be percent-escaped:

```raku
$ua.request: 'GET', 'http://john%40example.com:password@example.com/';
```

The `Authorization` header generated from these data will not be included
in a redirected request. If you want to avoid this behaviour you can set the
value manually, in which case it will not be modified or ignored.

The remaining named parameters are detailed below.

#### %headers

A map of headers to include with the request. If the value is a List of
strings, the header will be output multiple times, once with each value in the
array. The headers specified in this parameter overwrite any default ones.

The `Host` header is internally generated from the request URL [in accordance
with RFC 7230][host]. It is a fatal error to specify this header. Other
headers may be ignored or overwritten if necessary for transport compliance,
but this will in general be avoided.

[host]: https://tools.ietf.org/html/rfc7230#section-5.4

#### $content

A value to use for the body of the request, which can be a Blob, a Str or
Numeric, a Hash, or a Callable, with each of these modifying the default
assumptions about the request.

If `$content` is a Blob, the `Content-Type` header will default to
`application/octet-stream` and the contents of the Blob will be used as-is as
the body. The `Content-Length` header will also default to the number of
bytes in the Blob.

If `$content` is a Str or Numeric, it will be stringified by calling `Str`
on it and internally encoded as UTF-8 and converted to a Blob. The
`Content-Type` will in this case default to `text/plain;charset=UTF-8`,
but handling will otherwise be as detailed above.

If `$content` is a Hash, the default content type will depend on the values.
If any of the values is an IO::Path object it will be `multipart/form-data`,
otherwise it will be `application/x-www-form-urlencoded`.

If `$content` is a Callable, it will be called iteratively to produce the
body of the request. When called, it must return a Blob with the next part
of the body until the body has been fully generated, in which case it must
return an empty Blob, or a Blob type object.

Note that these behaviours are the *default* behaviours, and represent the
assumptions that will be made about the request based on the input.

When using a Callable, the `Content-Type` will default to
`application/octet-stream` and if no `Content-Length` header has been set,
the `Transfer-Encoding` will default to `chunked`, with each new part of the
body being sent in a separate chunk.

When using a Hash, its contents will be encoded depending on the value of the
`Content-Type` header. Using IO::Path objects as values is only supported
with multipart form encoding. If a value is a IO::Path, IO::Handle, or
anything that supports the `slurp` method, this will be called with the
`:bin` argument to provide the value of that key, and the content type will
be set to `application/octet-stream`. If using an IO::Path object, the
filename will be set to the result of calling `basename`.

If no value is set, no `Content-Type` or `Content-Length` headers will be
generated.

#### &data-callback

The data callback takes a block of code that will be executed once with each
chunk of the response body. The callback will be introspected to determine
how many arguments it can receive, and will be called with up to three
arguments each time:

* A Blob with the current encoded response chunk

* A Hash with the current state of the response Hash

* A Hash with the part headers (only for multipart responses)

This should allow customising the behaviour of the callback depending on the
response status or headers before receiving the full response body.

The callback must support at least the Blob argument. The other two are
optional. Not supporting any of these is an error.

#### &trailer-callback

When using a chunked transfer encoding, this callback will be called once after
the request body has been sent. It should return a Hash which will be used to
add trailing headers to the request.

#### The response Hash

The `request` method returns a Hash with the response. The Hash will have the
following keys:

success
: A Bool that will be true if the response status code starts with a 2.

url
: The URL that provided the response as a Str. This will be the URL provided by
the caller unless there were redirections, in which case it will be the last
URL queried in the redirection chain.

status
: The HTTP status code of the response as an Int.

reason
: The response phrase as provided by the server.

content
: The body of the response as a Buf[uint8]. This key will be missing if the
response had no content or if a data callback was provided to consume the
body. HTTP::Tiny will never automatically decode a response body.

headers
: A Hash of header fields. All header fields will be normalised to be lower
case. If a header is repeated, the value will be a List with the received
values as Str objects. Otherwise, the value will be a Str. Header values will
be decoded using ISO-8859-1 as per [RFC 7230 § 3.2.4].

protocol
: The protocol of the response, such as 'HTTP/1.1' or 'HTTP/1.0'.

redirects
: If this key exists, it will hold a List of response Hash objects from the
encountered redirects in the order they occurred. This key will no exist if
no redirection took place.

If an exception is encountered during execution, the `status` field will be
set to '599' and the `content` field will hold the text of the exception.

[RFC 7230 § 3.2.4]: https://tools.ietf.org/html/rfc7230#section-3.2.4

### mirror

```raku
method mirror (
    Str  $url,
    IO() $file,
        :$content,
        :%headers,
        :&trailer-callback,
) returns Hash
```

Executes a `GET` request for the URL and saves the response body to the
specified file. The URL must have unsafe characters escaped and
international domain names encoded. If the file already exists, the request
will include an `If-Modified-Since` header with the modification timestamp
of the file if none has already been provided in the `:%headers` parameter.
The parent directories of the file will not be automatically created.

The value of `$file` can be anything that implements an `.IO` method.

The `success` field of the response will be true if the status code is 2XX
or if the status code is 304 (unmodified).

If the file was modified and the server response includes a properly formatted
`Last-Modified` header, the file modification time will be updated
accordingly. Note that currently this makes use of the `touch` system
command,and will therefore not work if this command is not available.

### can-ssl

```raku
with HTTP::Tiny.can-ssl {
    # SSL support is available
}
else {
    note 'SSL support not available: ' ~ .exception.message;
}
```

Indicates if SSL support is available by checking for the correct version
of IO::Socket::SSL (greater than or equal to 0.0.2). It will either return
True if SSL support is available, or a Failure indicating why it isn't.

## PROXY SUPPORT

HTTP::Tiny can proxy both HTTP and HTTPS requests. Only Basic proxy
authorization is supported and it must be provided as part of the proxy URL,
as in `http://user:pass@proxy.example.com/`.

HTTP::Tiny supports the following proxy environment variables:

* `http_proxy` or `HTTP_PROXY`

* `https_proxy` or `HTTPS_PROXY`

* `all_proxy` or `ALL_PROXY`

An HTTPS connection may be made via an HTTP proxy that supports the
`CONNECT` method (cf. RFC 2817). If your proxy itself uses HTTPS, you can
not tunnel HTTPS over it.

Be warned that proxying an HTTPS connection opens you to the risk of a
man-in-the-middle attack by the proxy server.

The  `no_proxy` environment variable is supported in the format of a
comma-separated list of domain extensions proxy should not be used for.

Proxy arguments passed to `new` will override their corresponding
environment variables.

## LIMITATIONS

HTTP::Tiny aims to be *conditionally compliant* with the
[HTTP/1.1 specifications](http://www.w3.org/Protocols/):

* ["Message Syntax and Routing" [RFC7230]](https://tools.ietf.org/html/rfc7230)

* ["Semantics and Content" [RFC7231]](https://tools.ietf.org/html/rfc7231)

* ["Conditional Requests" [RFC7232]](https://tools.ietf.org/html/rfc7232)

* ["Range Requests" [RFC7233]](https://tools.ietf.org/html/rfc7233)

* ["Caching" [RFC7234]](https://tools.ietf.org/html/rfc7234)

* ["Authentication" [RFC7235]](https://tools.ietf.org/html/rfc7235)

It aims to meet all "MUST" requirements of the specification, but only some
of the "SHOULD" requirements.

Some particular limitations of note include:

*   HTTP::Tiny focuses on correct transport. Users are responsible for
    ensuring that user-defined headers and content are compliant with the
    HTTP/1.1 specification.

*   Users must ensure that URLs are properly escaped for unsafe characters
    and that international domain names are properly encoded to ASCII.

*   Redirection is very strict against the specification. Redirection is
    only automatic for response codes 301, 302, 307 and 308 if the request
    method is `GET` or `HEAD`. Response code 303 is always converted into a
    `GET` redirection, as mandated by the specification. There is no
    automatic support for status 305 ("Use proxy") redirections.

*   There is no provision for delaying a request body using an `Expect`
    header. Unexpected `1XX` responses are silently ignored as per the
    specification.

*   Only 'chunked' `Transfer-Encoding` is supported.

*   There is no support for a Request-URI of `*` for the `OPTIONS` request.

*   Headers mentioned in the RFCs and some other, well-known headers are
    generated with their canonical case. The order of headers is not
    preserved: control headers are sent first, while the remainder are sent
    in an unspecified order.

*   No mitigations for [httpoxy](https://httpoxy.org) have been implemented.
    If you are using this library under CGI, you are on your own.

## SEE ALSO

### [HTTP::UserAgent]

The de-facto blocking HTTP client for Raku, used by most applications. If a
feature you want is not supported by HTTP::Tiny, try using this distribution.
It is included in the Rakudo Star distribution, so chances are you already
have it.

That said, at the time of writing HTTP::UserAgent does not handle 1XX
responses, nor does it support chunked requests.

### [Cro::HTTP]

Part of the Cro family of libraries, it is written with asynchronous code as
its primary goal. Supports HTTP/2.0.

### [HTTP::Tinyish]

Another port from Perl, HTTP::Tinyish offers a similar interface to this
library while relying on an externally available `curl` binary.

### [LibCurl]

Raku bindings for libcurl. The bindings are fairly low-level, so they allow
for finer control than HTTP::Tinyish, but at the cost of a more complicated
interface.

### [LWP::Simple]

An older an more barebones blocking HTTP client for Raku, preceding the
development of HTTP::UserAgent.

### [Net::HTTP]

A library providing the building blocks to write your own HTTP client.
Supports connection caching and should be thread safe.

Code is fairly low-level, so use in real-world scenarios might require
some effort until more progress is done in the implementation of classes
like Net::HTTP::Client.

[HTTP::UserAgent]: https://modules.raku.org/dist/HTTP::UserAgent:github:github:sergot
[Cro::HTTP]: https://modules.raku.org/dist/Cro::HTTP:cpan:JNTHN
[HTTP::Tinyish]: https://modules.raku.org/dist/HTTP::Tinyish:cpan:SKAJI
[LibCurl]: https://modules.raku.org/dist/LibCurl:cpan:CTILMES
[LWP::Simple]: https://modules.raku.org/dist/LWP::Simple:github:Cosimo%20Streppone
[Net::HTTP]: https://modules.raku.org/dist/Net::HTTP:github:ugexe

## AUTHOR

José Joaquín Atria <jjatria@cpan.org>

## ACKNOWLEDGEMENTS

The code in this distribution is heavily inspired by that of
[the Perl library of the same name](https://metacpan.org/pod/HTTP::Tiny),
written by Christian Hansen and David Golden.

Some parts of the code have been adapted from existing solutions in the
HTTP::UserAgent codebase, which served as a reference on the use of Raku
toolbox.

## COPYRIGHT AND LICENSE

Copyright 2020 José Joaquín Atria

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.
