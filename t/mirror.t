#!/usr/bin/env raku

use lib 't/lib';
use HTTP::Tiny;
use HTTP::Tiny::Test;

my $ua = HTTP::Tiny.new: :allow-test-handle, :throw-exceptions;

subtest 'File does not exist' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-with-content'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like   $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    unlike $request, rx:i/ ^^ 'if-modified-since: ' /, 'Did not send header';
    is $out.slurp, 'Hello World!', 'Set file contents';
}

subtest 'File exists' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    $out.spurt: 'Old contents';

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-with-content'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    like $request, rx:i/ ^^ 'if-modified-since: ' /, 'Sent header';
    is $out.slurp, 'Hello World!', 'Set file contents';
}

subtest 'Last modified RFC1123' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-last-modified-rfc1123'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    is $out.slurp, 'Hello World!', 'Set file contents';

    todo 'Poor cross-platform support';
    is $out.modified.DateTime, '1994-11-06T08:49:37Z', 'Set last modified';
}

subtest 'Last modified RFC1036' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-last-modified-rfc1036'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    is $out.slurp, 'Hello World!', 'Set file contents';

    todo 'Poor cross-platform support';
    is $out.modified.DateTime, '1994-11-06T08:49:37Z', 'Set last modified';
}

subtest 'Last modified ANSI' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-last-modified-ansi'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    is $out.slurp, 'Hello World!', 'Set file contents';

    todo 'Poor cross-platform support';
    is $out.modified.DateTime, '1994-01-02T08:49:37Z', 'Set last modified';
}

subtest 'Last modified invalid' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/200-last-modified-invalid'.IO,
    );

    my $res = $ua.mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    is $out.slurp, 'Hello World!', 'Set file contents';

    todo 'Poor cross-platform support';
    isnt $out.modified.DateTime, '1994-11-06T08:49:37Z', 'Did NOT set last modified';
}

subtest 'Not modified' => {
    my $out = "t/mirror-{ ( ^2**32 ).pick }.out".IO;
    LEAVE try $out.unlink;

    $out.spurt: 'Old contents';

    my Str $request;
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $data { $request ~= $data },
        response => 't/res/get/304-not-modified'.IO,
    );

    my $res = HTTP::Tiny.new( max-redirect => 0, :allow-test-handle )
        .mirror( 'http://localhost:1234/foo', $out );

    like $request, rx/ ^ 'GET /foo' /, 'Sent a GET request';
    is $out.slurp, 'Old contents', 'Contents remain the same';
    ok $res<success>, '304 responses are successes';
}

done-testing;
