#!/usr/bin/env raku

use lib 't/lib';
use HTTP::Tiny;
use HTTP::Tiny::Test;

my $ua = HTTP::Tiny.new( :throw-exceptions, :allow-test-handle );
my @tests = (
    GET => '/404-not-found',
    GET => '/500-server-error',
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

    throws-like { $ua.request: $method, 'http://localhost:1234' ~ $path },
        X::HTTP::Tiny,
        message => %want< status reason >.join(' ');
}

subtest 'Custom 599 response' => {
    my $*HTTP-TINY-HANDLE = Test::Handle.new(
        writer   => -> $ { die 'Something terrible happened' },
        response => 't/res/get/200-with-content'.IO,
    );

    # Throws an exception if :throw-exceptions is set
    throws-like { $ua.get('http://localhost:1234/foo') },
        X::HTTP::Tiny,
        message => 'Something terrible happened';

    my $res = HTTP::Tiny.new(:allow-test-handle)
        .get( 'http://localhost:1234/foo' );

    $res.&is-deeply: {
        success => False,
        status  => 599,
        reason => 'Internal Exception',
        content => Buf[uint8].new( 'Something terrible happened'.encode ),
        headers => {
            content-type   => 'text/plain',
            content-length => 27,
        },
    }, 'Caught internal exception in custom error response';
}

done-testing;
