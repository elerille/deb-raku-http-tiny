#!/usrbin/env raku

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
