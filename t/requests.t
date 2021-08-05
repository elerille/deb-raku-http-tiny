#!/usr/bin/env raku

use lib 't/lib';
use HTTP::Tiny;
use HTTP::Tiny::Test;

my &from-json = { Rakudo::Internals::JSON.from-json: $^a }
my &to-json = { Rakudo::Internals::JSON.to-json: $^a }

my @tests = (
    GET  => '/basic-headers',
    GET  => '/basic-auth',
    GET  => '/default-headers',
    POST => '/with-body',
    POST => '/multipart-form-data-with-file',
    POST => '/multipart-form-data',
    POST => '/form-urlencoded',
    POST => '/chunked-body-with-trailer',
);

for @tests -> ( :key($method), :value($path) ) {
    my $check = 't/req'.IO
        .child( $method.lc )
        .child( $path );

    my $file = $check.extension( 'json', :!parts );

    unless $file.e {
        flunk "No such request file: $file";
        next;
    }

    unless $check.e {
        flunk "No such check file: $check";
        next;
    }

    my $out = $file.extension: 'out';
    LEAVE try $out.unlink;

    my $*HTTP-TINY-HANDLE = Request::Handle.new: :$out;

    my %params = Rakudo::Internals::JSON.from-json: slurp $file;

    with %params<request><named><content> {
        for .values.grep: *.starts-with('@') {
            $_ = .substr(1).IO;
        }
    }

    with %params<request><named><trailer-callback> {
        my $trailer = $_;
        $_ = sub { return $trailer };
    }

    my $ua = HTTP::Tiny.new:
        agent => 'HTTP-Tiny',
        :throw-exceptions,
        :allow-test-handle, |%params<new>;

    my $request = \( |%params<request><positional>, |%params<request><named> );
    $ua.request: |$request;

    $out.slurp.&is: $check.slurp, "$method $path" or do {
        my &hexdump = *.slurp.encode».fmt('%02X').join: ' ';
        diag 'Have: ' ~ $out.&hexdump;
        diag 'Want: ' ~ $check.&hexdump;
    }
}

subtest 'Redirect with basic auth' => {
    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $blob { $request ~= $blob.decode },
        response => [
            't/res/get/301-1-step-chain'.IO,
            't/res/get/200-with-content'.IO,
        ],
    );

    my $res = HTTP::Tiny.new( :allow-test-handle )
        .get( 'http://foo%40bar.com:hello world@localhost:1234/foo' );

    $request ~~ m:g/ ^^ [ 'Authorization: Basic ' $<auth> = \S+ ] /;
    is $/».<auth>».Str,
        [ 'Zm9vQGJhci5jb206aGVsbG8gd29ybGQ=' ], # echo -n 'foo@bar.com:hello world' | base64
        'Authorization header not sent on redirects';
}

subtest 'Redirect with basic auth manually set headers' => {
    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $blob { $request ~= $blob.decode },
        response => [
            't/res/get/301-1-step-chain'.IO,
            't/res/get/200-with-content'.IO,
        ],
    );

    my $res = HTTP::Tiny.new( :allow-test-handle ).get(
        'http://localhost:1234/foo',
        headers => {
            authorization => 'Basic Zm9vQGJhci5jb206aGVsbG8gd29ybGQ=',
        },
    );

    # echo -n 'foo@bar.com:hello world' | base64
    $request ~~ m:g/ ^^ [ 'Authorization: Basic Zm9vQGJhci5jb206aGVsbG8gd29ybGQ=' ] /;

    is $/».<auth>.elems, 2,
        'Authorization header sent on redirects if manually set';
}

done-testing;
