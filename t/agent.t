#!/usr/bin/env raku

use HTTP::Tiny;
use Test;

class HTTP::Lite is HTTP::Tiny {}

like get-agent(HTTP::Tiny.new), rx{^ 'HTTP::Tiny/'};

like get-agent(HTTP::Lite.new), rx{^ 'HTTP::Lite/'};

is get-agent(HTTP::Tiny.new: :agent<Foo>), 'Foo';

is get-agent(HTTP::Lite.new: :agent<Foo>), 'Foo';

done-testing;

sub get-agent { $^ua.^attributes.first(*.name eq '$!agent').get_value: $ua }
