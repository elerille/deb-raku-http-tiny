#!/usr/bin/env raku

use lib 't/lib';
use HTTP::Tiny;
use HTTP::Tiny::Test;

my $ua = HTTP::Tiny.new: :allow-test-handle;

my %tests = (
    'HtTp://Example.COM/'                 => ( 'http',  'example.com',   80, '/'         ),
    'HtTp://Example.com:1024/'            => ( 'http',  'example.com', 1024, '/'         ),
    'http://example.com'                  => ( 'http',  'example.com',   80, '/'         ),
    'http://example.com:'                 => ( 'http',  'example.com',   80, '/'         ),
    'http://foo@example.com:'             => ( 'http',  'example.com',   80, '/'         ),
    'http://@example.com:'                => ( 'http',  'example.com',   80, '/'         ),
    'http://example.com?foo=bar'          => ( 'http',  'example.com',   80, '/?foo=bar' ),
    'http://example.com?foo=bar#fragment' => ( 'http',  'example.com',   80, '/?foo=bar' ),
    'HTTPS://example.com/'                => ( 'https', 'example.com',  443, '/'         ),
    'xxx://foo/'                          => ( 'xxx',   'foo',          Int, '/'         ),
);

for %tests.kv -> $url, @parts is copy {
    my $scheme = shift @parts;

    my $out = "t/url-parsing-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my $*HTTP-TINY-HANDLE = Request::Handle.new: :$out;
    my $res = $ua.get: $url;

    with $out.slurp ~~ /
        ^  'GET '   $<path> = \S+ .*
        ^^ 'Host: ' $<host> = \S+
    / {
        my ( $path, $host, $port ) = ~$<path>, |$<host>.split: ':';

        $port =  $port              ?? +$port
              !! $scheme eq 'https' ?? 443
              !! $scheme eq 'http'  ?? 80
              !! Int;

        is-deeply [ $host, $port, $path ], @parts, $url or diag slurp $out;
    }
    else {
        flunk "Did not match URL: $url";
    }
}

done-testing;
