#!/usr/bin/env raku

use Test;
use HTTP::Tiny;

unless %*ENV<ONLINE_TESTING> {
    say '1..0 # SKIP: ONLINE_TESTING not set';
    exit;
}

my &from-json = { Rakudo::Internals::JSON.from-json: $^a }
my &to-json = { Rakudo::Internals::JSON.to-json: $^a }

my $ua = HTTP::Tiny.new;
for < http https > -> $scheme {
    for < get post > -> $method {
        if $scheme eq 'https' {
            without HTTP::Tiny.can-ssl {
                skip 'No SSL support: ' ~ .exception.message;
                next;
            }
        }

        diag 'Default multipart form with file upload';
        do-test(
            $ua."$method"(
                "$scheme://httpbin.org/anything?foo=bar",
                content => {
                    file => 't/text-file.txt'.IO,
                    list => [ 123, 456 ],
                },
            ),
            {
                args  => { foo  => 'bar' },
                files => { file => "Hello World! 🌍\n" },
                form  => { list => [ '123', '456' ] },
            },
        );

        diag 'Default URL encoded form';
        do-test(
            $ua."$method"(
                "$scheme://httpbin.org/anything?zipi=zape",
                content => {
                    username => 'pat-span',
                    password => 'password',
                },
            ),
            {
                args  => { zipi => 'zape' },
                files => { },
                form  => { username => 'pat-span', password => 'password' }
            },
        );

        diag 'No body';
        do-test(
            $ua."$method"( "$scheme://httpbin.org/anything" ),
            {
                args  => { },
                files => { },
                form  => { },
            },
        );
    }
}

done-testing;

sub do-test ( $res, %want ) {
    my $content = from-json $res<content>.decode;
    my %have = %want.keys.map: { $_ => $content{$_} }

    subtest "$content<method> $content<url>" => {
        ok $res<success>, 'Request was succesful';
        is-deeply %have, %want, 'Matches expected output';
    }
}
