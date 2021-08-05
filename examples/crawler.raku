#!/usr/bin/env raku

use v6;
use HTTP::Tiny;

sub MAIN (Str $start-url) {
    my $ua = HTTP::Tiny.new: :agent<chrome_linux>, :throw-exceptions;
    my @urls = $start-url;

    while @urls.shift -> $url {
        print "Trying: $url ... ";

        CATCH {
            default { say '[NOT OK]' }
        }

        my $res = $ua.get: $url;
        my $content = .<content>.decode with $res;

        say '[OK]';
        @urls.push: |( $content.&get-urls (-) @urls ).keys;
    }
}

sub get-urls ( Str $content ) {
    return .map( *.<url>.subst: / \/ $/, '' ) with $content ~~ m:g/
        'href="' $<url> = [ 'http' <-[ # " ]>+ ]
    /;
}
