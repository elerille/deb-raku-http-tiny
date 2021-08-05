#!/usr/bin/env raku

use Test;
use HTTP::Tiny;

unless %*ENV<ONLINE_TESTING> {
    say '1..0 # SKIP: ONLINE_TESTING not set';
    exit;
}

my $ua = HTTP::Tiny.new;
for < http https > -> $scheme {
    subtest "{ $scheme.uc } tests" => {
        if $scheme eq 'https' && !HTTP::Tiny.can-ssl {
            skip 'No HTTPS support';
        }
        else {
            await ( ^10 ).map: -> $i {
                start {
                    my $res = $ua.get: "$scheme://httpbin.org/status/200";
                    ok $res<success>, "Finished request $i" or dd $res;
                }
            }
        }
    }
}

done-testing;
