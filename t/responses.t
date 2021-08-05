#!/usr/bin/env raku

use lib 't/lib';
use HTTP::Tiny;
use HTTP::Tiny::Test;

my $ua = HTTP::Tiny.new: keep-alive => False, max-redirect => 2, :allow-test-handle;
my @tests = (
    GET => '/100-followed-by-200',
    GET => '/200-with-content',
    GET => '/200-without-content-length',
    GET => '/200-with-extra-content',
    GET => '/200-with-headers',
    GET => '/200-insane-continuations',
    GET => '/200-chunked-content',
    GET => '/200-chunked-content-unannounced-trailer',
    GET => '/200-chunked-content-no-trailer',
    GET => '/200-opaque-header',
    GET => '/204',
    GET => '/206-multipart-response',
    GET => '/301-1-step-chain',
    GET => '/301-2-step-chain',
    GET => '/301-3-step-chain',
    POST => '/303-becomes-get',
);

for @tests -> ( :key($method), :value($path) ) {
    my $file = 't/res'.IO
        .child( $method.lc )
        .child( $path );

    my $check = $file.extension( 'json', :!parts );

    unless $file.e {
        flunk "No such response file: $file";
        next;
    }

    unless $check.e {
        flunk "No such check file: $check";
        next;
    }

    my $*HTTP-TINY-HANDLE = Response::Handle.new;

    my %want = Rakudo::Internals::JSON.from-json: slurp $check;
    $_ = Buf[uint8].new: .encode with %want<content>;
    for %want<redirects>.grep( *.defined )  {
        $_ = Buf[uint8].new: .encode with .<content>;
    }

    my %have = $ua.request( $method, 'http://localhost:1234' ~ $path );
    %have.&is-deeply(
        %want,
        "$method $path",
    ) or do {
        my &hexdump = *».fmt('%02X').join: ' ';
        diag 'Have: ' ~ %have<content>.&hexdump;
        diag 'Want: ' ~ %want<content>.&hexdump;
    }
}

subtest 'Only read from handle what is left from content when known' => {
    my @read-bytes;
    state @response =
        Buf[uint8].new( "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n".encode ),
        Buf[uint8].new( '1234567890'.encode );

    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        reader => -> $bytes {
            @read-bytes.push: $_ with $bytes;
            @response.shift;
        },
    );

    my $res = HTTP::Tiny.new( :throw-exceptions, :allow-test-handle ).get(
        'http://localhost:1234/limited-read',
    );

    ok $res<success>, 'Request succeeded';
    is $res<content>.decode, '1234567890';
    @read-bytes.&is-deeply: [ 10 ], 'Read only 10 bytes';
}

done-testing;
