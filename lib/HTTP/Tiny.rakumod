class X::HTTP::Tiny is Exception {
    has     $.response is required;
    has Str $.message  is required;
}

class HTTP::Tiny:ver<0.1.6>:auth<cpan:JJATRIA> {
    my class Handle  { ... }
    my subset HTTPMethod of Str where /
        ^
        [ GET
        | CONNECT
        | DELETE
        | HEAD
        | OPTIONS
        | PATCH
        | POST
        | PUT
        | TRACE
        ]$
    /;

    has        %!proxy;
    has        %!no-proxy;
    has Handle $!handle;
    has        %!default-headers   is built;
    has Int    $!max-redirect      is built = 5;
    has Bool   $!keep-alive        is built = True;
    has Bool   $!throw-exceptions  is built;
    has Bool   $!allow-test-handle is built; # Undocumented, for testing only
    has Str    $!agent             is built
        = self.^name ~ '/' ~ $?DISTRIBUTION.meta<ver> ~ ' Raku';

    submethod TWEAK (
           :$no-proxy = %*ENV<   no_proxy>,
              :$proxy = %*ENV<  all_proxy> // %*ENV<  ALL_PROXY>,
         :$http-proxy = %*ENV< http_proxy> // %*ENV< HTTP_PROXY> // $proxy,
        :$https-proxy = %*ENV<https_proxy> // %*ENV<HTTPS_PROXY> // $proxy,
    ) {
        try $http-proxy.&split-url
            or die "Invalid HTTP proxy: $http-proxy";

        try $https-proxy.&split-url
            or die "Invalid HTTPS proxy: $https-proxy";

        %!proxy<http>  = $_ with $http-proxy;
        %!proxy<https> = $_ with $https-proxy;

        return unless $no-proxy;

        %!no-proxy = $no-proxy ~~ Str
            ?? $no-proxy.split(',')».trim.Set
            !! $no-proxy.Set;
    }

    method get     (|c) { self.request: 'GET',     |c }
    method delete  (|c) { self.request: 'DELETE',  |c }
    method head    (|c) { self.request: 'HEAD',    |c }
    method options (|c) { self.request: 'OPTIONS', |c }
    method patch   (|c) { self.request: 'PATCH',   |c }
    method post    (|c) { self.request: 'POST',    |c }
    method put     (|c) { self.request: 'PUT',     |c }
    method trace   (|c) { self.request: 'TRACE',   |c }

    multi method can-ssl ( --> Bool ) {
        # FIXME: Is there no easier way to do this?
        fail 'IO::Socket::SSL:ver<0.0.2+> must be installed'
            unless $*REPO.repo-chain
                .map( *.?candidates: 'IO::Socket::SSL', :ver<0.0.2+> )
                .flat.first( *.defined );
        return True;
    }

    multi method mirror ( ::?CLASS:U: |c ) { self.new.mirror: |c }

    multi method mirror (
        ::?CLASS:D:
             Str:D $url,
              IO() $file,
                  :%headers is copy,
                  |rest,
    ) {
        die 'data-callback is not allowed in mirror method'
            if rest<data-callback>:exists;

        my constant DoW = [< Mon Tue Wed Thu Fri Sat Sun >];
        my constant MoY = [< Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec >];

        sub format-date ( DateTime $dt --> Str ) {
            given $dt {
                return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT',
                    DoW[ .day-of-week - 1 ],
                    .day-of-month,
                    MoY[ .month -1 ],
                    .year,
                    .hour,
                    .minute,
                    .second;
            }
        }

        sub parse-date ( Str $date --> DateTime ) {
            my %args;
            given $date {
                # Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
                when /
                    ^
                    <{ DoW }>                     ',' ' '+
                    $<day>   =   \d ** 1..2           ' '+
                    $<month> = <{ MoY }>              ' '+
                    $<year>  =   \d ** 4              ' '+
                    $<hms>   = [ \d ** 2 ] ** 3 % ':' ' '+
                    GMT
                    $
                / {
                    %args = $/.hash;
                }

                # Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
                when /
                    ^
                    < Mon | Tues | Wednes | Thurs | Fri | Satur | Sun > 'day,' ' '+
                    $<day>   =   \d ** 2                                       '-'
                    $<month> = <{ MoY }>                                       '-'
                    $<year>  =   \d ** 2                                       ' '+
                    $<hms>   = [ \d ** 2 ] ** 3 % ':'                          ' '+
                    GMT
                    $
                / {
                    %args = $/.hash;
                    %args<year> = $<year> + 1900;
                }

                # Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
                when /
                    ^
                    <{ DoW }>                         ' '+
                    $<month> = <{ MoY }>              ' '+
                    $<day>   =   \d ** 1..2           ' '+
                    $<hms>   = [ \d ** 2 ] ** 3 % ':' ' '+
                    $<year>  =   \d ** 4
                    $
                / {
                    %args = $/.hash;
                }

                default { return DateTime }
            }

            my $hms = %args<hms>:delete;
            my ( $hour, $minute, $second ) = $hms.split(':').map: *.Int;

            my $month = MoY.antipairs.Map.{ %args<month>:delete } + 1;

            return DateTime.new: |%args, :$month, :$hour, :$minute, :$second;
        }

        self!normalise-headers: %headers;

        if $file.e {
            %headers<if-modified-since> ||= $file.modified.DateTime.&format-date;
        }

        my $tempfile = $file ~ (^2**31).pick;
        my $fh = open $tempfile, :x;
        LEAVE {
            $fh.close;
            $tempfile.IO.unlink;
        }

        my &data-callback = -> $blob { $fh.write: $blob }

        my %res;
        CATCH {
            when X::HTTP::Tiny && .response<status> == 304 { %res = .response }
        }

        %res = self.request: 'GET', $url, :&data-callback, :%headers, |rest;

        if %res<success> {
            $tempfile.IO.rename: $file;

            with ( %res<headers><last-modified> // '' ).&parse-date {
                my $timestamp = sprintf '%4d-%02d-%02d %02d:%02d:%02d',
                    .year, .month, .day, .hour, .minute, .second;

                CATCH {
                    when X::Proc::Unsuccessful {
                        note "Could not set modified time. Should be { .Str }";
                    }
                }

                # FIXME: We need to touch the file cross-platform
                run < touch -m -d >, $timestamp, $file, :!err;
            }
        }

        %res<success> ||= %res<status> == 304;

        return %res;
    }

    proto method request( :%headers, |c ) {
        die "The 'Host' header must not be provided as header option"
            if %headers.keys.first: { .defined && m:i/ ^ host $ / }
        {*}
    }

    # Support requests as class methods
    multi method request ( ::?CLASS:U: |c ) { self.new.request: |c }

    # FIXME: Why do these not work with nextwith?
    multi method request ( ::?CLASS:D: Any:U :$content, |c ) { samewith( |c ) }

    multi method request ( ::?CLASS:D: Numeric:D :$content, |c ) {
        samewith( content => $content.Str, |c );
    }

    multi method request (
        ::?CLASS:D:
             Str:D :content($input-content),
                   :%headers is copy,
                   |c,
    ) {
        self!normalise-headers: %headers;

        %headers<content-type> ||= 'text/plain;charset=UTF-8';
        my $content = Blob.new: $input-content.Str.encode;

        samewith( :%headers, :$content, |c );
    }

    multi method request (
        ::?CLASS:D:
            Hash:D :content($input-content),
                   :%headers is copy,
                   |c,
    ) {
        self!normalise-headers: %headers;

        # Default content types
        if $input-content.values.grep: IO::Path {
            my $type = %headers<content-type> ||= 'multipart/form-data';

            die "Cannot send a $type body with a Hash with IO::Path values"
                unless $type.starts-with: 'multipart/form-data';
        }
        else {
            %headers<content-type>
                ||= 'application/x-www-form-urlencoded';
        }

        # Encode form data
        my $content;
        given %headers<content-type> -> $type {
            when $type.starts-with: 'multipart/form-data' {
                my $boundary;
                if $type ~~ / 'boundary=' \"? ( <-["]>+ ) / {
                    $boundary = $0;
                }
                else {
                    $boundary = ('a'...'z', 'A'...'Z').roll(20).join;
                    %headers<content-type> ~= Q:s'; boundary="$boundary"';
                }

                $content = $input-content.&multipart-encode: $boundary;
            }
            when $type eq 'application/x-www-form-urlencoded' {
                $content = Blob.new: $input-content.&url-encode.encode;
            }
            default {
                die "Cannot send a $type body with a Hash";
            }
        }

        samewith( :%headers, :$content, |c );
    }

    multi method request (
        ::?CLASS:D:
            Blob:D :content($input-content),
                   :%headers is copy,
                   |c,
    ) {
        self!normalise-headers: %headers;

        %headers<content-length> ||= $input-content.bytes
            unless %headers<transfer-encoding>;

        my $source = $input-content;
        my &content = sub ( --> Blob ) {
            LEAVE $source = Blob.new;
            return $source.subbuf: 0, $source.bytes;
        }

        samewith( :%headers, :&content, |c );
    }

    multi method request (
        ::?CLASS:D:
        HTTPMethod $method,           # A valid HTTP verb, in uppercase
        Str        $url,              # The URL to send the request to
                  :%headers is copy,  # The set of headers to send as a Hash
                  :&data-callback,    # An optional callback for content chunks
                  :&trailer-callback, # An optional callback to generate the trailer
                  :&content           # A Str, Blob, or Callable for the content
    ) {
        self!normalise-headers: %headers;

        if &content {
            %headers<content-type>      ||= 'application/octet-stream';
            %headers<transfer-encoding> ||= 'chunked'
                unless %headers<content-length>;
        }

        my $response = self!request: $method, $url,
            :%headers, :&content, :&data-callback, :&trailer-callback;

        if $!throw-exceptions && ! $response<success> {
            my $message = $response<status> == 599
                ?? $response<content>.decode
                !! $response< status reason >.join: ' ';

            .throw with X::HTTP::Tiny.new: :$response, :$message;
        }

        return $response;
    }

    # END OF PUBLIC API

    sub split-url ( Str:D $url ) {
        $url ~~ /
            ^
            $<scheme>     = <-[ : / ? # ]>+
            '://'
            $<authority>  = <-[   / ? # ]>+
            $<path>       = <-[       # ]>*
        / or die "Cannot parse URL: $url";

        my $scheme = lc $<scheme>;
        my $path   = ~$<path>;
           $path   = "/$path" unless $path.starts-with: '/';

        my ( $host, $auth ) = $<authority>.flip.split( '@', 2 )».flip;
        $auth .= &url-decode with $auth;

        my Int $port = $host ~~ / ':' $<port> = \d+ $ / ?? +$<port>
            !! $scheme eq 'http'                        ?? 80
            !! $scheme eq 'https'                       ?? 443
            !! Nil;

        s/ ':' \d* $ // given $host;

        return $scheme, $host.lc, $port, $path, $auth;
    }

    sub base64-encode ( Blob $blob --> Str ) {
        my constant %enc = ( 'A'...'Z', 'a'...'z', 0...9, '+', '/' ).pairs;

        my $out = $blob».fmt('%08b').join.comb(6)
            .map({ %enc{ .fmt('%-6s').subst(' ', '0', :g).parse-base(2) } })
            .join;

        $out ~= '=' while $out.chars % 4;

        return $out;
    }

    multi sub url-decode ( Str:D $text --> Str ) {
        return $text.subst: / '%' ( <xdigit> ** 2 ) /,
            { $0.Str.parse-base(16).chr }, :g;
    }

    # Encodes for URL encoded forms
    multi sub url-encode ( Str() $text --> Str ) {
        return $text.subst:
            /<-[
                ! * ' ( ) ; : @ + $ , / ? # \[ \]
                0..9 A..Z a..z \- . ~ _
            ]> /,
            { .Str.encode».fmt('%%%02X').join }, :g;
    }

    multi sub url-encode ( Hash $form --> Str ) {
        return join '&', gather for $form.sort -> ( :$key, :$value ) {
            take "$key={ .&url-encode }" for $value.List;
        }
    }

    sub multipart-encode ( %form, $boundary --> Blob ) {
        my $blob = Blob.new;
        for %form.sort -> ( :key($key), :value($v) ) {
            for $v.List -> $value {
                $blob ~= "--$boundary\r\n".encode;
                $blob ~= "Content-Disposition: form-data; name=\"$key\"".encode;

                if $value.^lookup: 'slurp' {
                    if $value ~~ IO::Path {
                        $blob ~= qq[; filename="{ $value.basename }"].encode;
                    }
                    $blob ~= "\r\n".encode;
                    $blob ~= "Content-Type: application/octet-stream\r\n\r\n".encode;
                    $blob ~= $value.slurp: :bin;
                    $blob ~= "\r\n".encode;
                    next;
                }

                $blob ~= "\r\n\r\n$value\r\n".encode;
            }
        }
        $blob ~= "--$boundary--\r\n".encode;

        return $blob;
    }

    # Lowercases top-level keys in a Hash and sets default values
    method !normalise-headers ( ::?CLASS:D: %h ) {
        %h{ .lc }       = %h{$_} for %h.keys.grep: /<upper>/;
        %h{ .key.lc } ||= .value for %!default-headers;
        return;
    }

    # Well-known header capitalisation exceptions. All other headers will be
    # capitalised automatically to match the common standard.
    # Bear in note that header field names are case-insensitive in any case:
    # https://tools.ietf.org/html/rfc7230#section-3.2
    my constant HEADER-CASE =
        < TE Content-MD5 DNT X-XSS-Protection >.map({ .lc => $_ }).Map;

    method !request (
        Str $method,
        Str $url,
           :%headers,
           :&data-callback,
           :&trailer-callback,
           :&content,
           :%state = {},
    ) {
        CATCH {
            when X::HTTP::Tiny { return .response }

            default {
                my $content = Buf[uint8].new: .message.encode;
                return {
                    :$content,
                    success => False,
                    status  => 599,
                    reason  => 'Internal Exception',
                    headers => {
                        content-length => $content.bytes,
                        content-type   => 'text/plain',
                    },
                }
            }
        }

        # TODO: Cookies

        my ( $scheme, $host, $port, $path, $auth ) = split-url($url);

        # If we have Basic auth parameters, add them
        my Bool $basic-auth;
        if $auth && !%headers<authorization> {
            $basic-auth = True;
            %headers<authorization> = "Basic { $auth.encode.&base64-encode }";
        }

        %headers<host> = $host;
        %headers<host> ~= ":$port"
            if ( $scheme eq 'https' && $port != 443 )
            || ( $scheme eq 'http'  && $port !=  80 );

        %headers<connection> = 'close' unless $!keep-alive;
        %headers<user-agent> ||= $!agent;

        my $handle = $!handle and $!handle = Nil;
        if $handle && not $handle.can-reuse: $scheme, $host, $port {
            $handle.close;
            $handle = Nil;
        }
        $handle //= Handle.new;

        if !%!no-proxy{$host} && %!proxy{$scheme} {
            my $proxy = %!proxy{$scheme};

            %headers<proxy-authorization> = "Basic { .encode.&base64-encode }"
                with $proxy.&split-url.tail;

            $handle.connect: $proxy, :$!allow-test-handle;

            if $scheme eq 'https' {
                $handle.upgrade: "$host:$port", %headers;
            }
            else {
                $path = $url;
            }
        }
        else {
            $handle.connect: $url, :$!allow-test-handle;
        }

        $handle.write-request: $method, $path,
            %headers, &content, &trailer-callback;

        my ( %response, Blob[uint8] $head, Blob[uint8] $body );
        repeat while %response<status>.starts-with: '1' {
            ( $head, $body ) = $handle.get-response-header: $body;
            %response = $handle.read-response-header($head);
        }

        %response<url> = $url;

        my Bool $known-length;
        if $method ne 'HEAD' && %response<status> != 204 | 304 {
            # Any time we receive a relevant chunk of content, we'll pass
            # that to &on-content. If the user provided a 'data-callback'
            # then that defined what we call. If not, we'll provide our
            # own.
            # This means the code past this point can always assume there
            # is a callback to use, which makes this easy to extend.
            # What constitutes 'a relevant chunk of content' will depend on
            # the response type. It might be just a blob of data in a
            # fixed-length response, or a chunk in a chunked response, or
            # a part in a multipart response, etc.
            # The cando check is because, when dealing with multipart
            # responses, we need to provide the user with the part's headers
            # (eg. so they can identify the byterange it belongs to), but
            # it would be cumbersome to always require a callback that
            # accepted 3 parameters, some of which will never be used.
            my Buf[uint8] $response-body .= new;
            my &on-content;
            with &data-callback {
                # FIXME: Why does when not work here?
                if .cando: \( Blob, Hash, Hash ) {
                    &on-content = &data-callback.assuming( *, %response, * );
                }
                elsif .cando: \( Blob, Hash ) {
                    &on-content = &data-callback.assuming( *, %response );
                }
                elsif .cando: \( Blob ) {
                    &on-content = &data-callback;
                }
                else {
                    die 'Unsupported signature for data callback: ' ~ .signature.raku;
                }
            }
            else {
                &on-content = { $response-body.append: $^blob }
            }

            # read-content will add any trailing headers if parsing
            # a chunked response
            $known-length = $handle.read-content: &on-content, $body, %response;

            %response<content> = $response-body
                if !&data-callback && $response-body.bytes;
        }

        my $see-other = %response<status> == 303;
        my $redirect  = %response<status> ~~ / ^ 30 <[ 1 2 7 8 ]> $ /
            && $method eq 'GET' | 'HEAD'
            && %response<headers><location>;

        if ( $see-other || $redirect )
            && %state<redirects>.elems < $!max-redirect
        {
            %state<redirects>.push: %response;

            %headers<authorization>:delete if $basic-auth;

            my $location = %response<headers><location>;
            $location = sprintf '%s://%s:%s%s',
                $scheme,
                $host,
                $port,
                $location if $location.starts-with: '/';

            return self!request: $see-other ?? 'GET' !! $method,
                $location, :%headers, :&data-callback, :%state;
        }

        %response<redirects> = $_ with %state<redirects>;

        if $!keep-alive
            && $known-length
            && %response<protocol> eq 'HTTP/1.1'
            && quietly %response<headers><connection> ne 'close'
        {
            $!handle = $handle;
        }
        else {
            $handle.close;
        }

        return %response;
    }

    my class Handle {
        my constant BUFFER-SIZE = 32_768;

        has Str        $!scheme;
        has Str        $!host;
        has Int        $!port;
        has Thread     $!thread;
        has Int        $!timeout          is built = 180;
        has Int        $!max-header-lines is built = 64;
        has IO::Socket $!handle handles 'close';

        my Lock $lock .= new;

        method connect (
            ::?CLASS:D:
                 Str:D $url,
                 Bool :$allow-test-handle,
        ) {
            my ( $scheme, $host, $port ) = split-url($url);

            die "Unsupported URL host '$host'"
                if $host ~~ / ^ '[' .* ']' $ /;

            given $scheme {
                when $allow-test-handle && $*HTTP-TINY-HANDLE.defined {
                    $!handle = $*HTTP-TINY-HANDLE;
                }
                when 'https' {
                    with HTTP::Tiny.can-ssl {
                        $lock.lock;
                        try require ::('IO::Socket::SSL');
                        $lock.unlock;

                        die 'Cold not load IO::Socket::SSL'
                            if ::('IO::Socket::SSL') ~~ Failure;

                        $!handle = ::('IO::Socket::SSL').new: :$host, :$port;
                    }
                    else {
                        die "HTTPS requests not supported: { .exception.message }";
                    }
                }
                when 'http' {
                    $!handle = IO::Socket::INET.new: :$host, :$port;
                }
                default {
                    die "Unsupported URL scheme '$scheme'";
                }
            }

            $!host   = $host;
            $!port   = $port;
            $!scheme = $scheme;
            $!thread = $*THREAD;

            return;
        }

        method upgrade ( Str $url, %headers ) {
            die "HTTPS requests not supported: { .exception.message }"
                without HTTP::Tiny.can-ssl;

            my %connect-headers = (
                host => $url,
                user-agent => %headers<user-agent>
            );

            %connect-headers<proxy-authorization>
                = $_ with %headers<proxy-authorization>:delete;

            self.write-request: 'CONNECT', $url, %connect-headers;

            my ( %response, Blob[uint8] $head, Blob[uint8] $body );
            repeat while %response<status>.starts-with: '1' {
                ( $head, $body ) = self.get-response-header: $body;
                %response = self.read-response-header($head);
            }

            # If CONNECT failed, throw the response so it will be
            # returned from the original request() method;
            unless %response<success> {
                my $message = %response<status> == 599
                    ?? %response<content>.decode
                    !! %response< status reason >.join: ' ';

                X::HTTP::Tiny.new( :%response, :$message ).throw;
            }

            # Upgrade plain socket to SSL now that tunnel is established
            $lock.lock;
            try require ::('IO::Socket::SSL');
            $lock.unlock;

            die 'Cold not load IO::Socket::SSL'
                if ::('IO::Socket::SSL') ~~ Failure;

            $!handle = ::('IO::Socket::SSL').new: client-socket => $!handle;

            return;
        }

        submethod DESTROY { try $!handle.close }

        multi method can-reuse ( ::?CLASS:U: |c --> False ) {;}
        multi method can-reuse ( ::?CLASS:D: $scheme, $host, $port --> Bool ) {
            return $!thread ~~ $*THREAD
                && $!scheme eq $scheme
                && $!host   eq $host
                && $!port   == $port;
        }

        my constant   LINE-END = Blob[uint8].new: 13, 10;
        my constant HEADER-END = Blob[uint8].new: 13, 10, 13, 10;

        my sub blob-search ( Blob[uint8] $haystack, Blob[uint8] $needle --> Int ) {
            my Int $end;
            my $length = $needle.bytes;
            while ++$end < $haystack.bytes {
                return $end if $needle eq $haystack.subbuf: $end, $length;
            }
            return Int;
        }

        method write-request (
            $method,
            $path,
            %headers,
            &content?,
            &trailer-callback?,
        ) {
            self.write-request-header: $method, $path, %headers;
            return unless defined &content;
            return self.write-request-body: $_, &content
                with %headers<content-length>;
            return self.write-chunked-body: &content, &trailer-callback;
        }

        method write-request-header ( $method, $path, %headers ) {
            given "$method $path HTTP/1.1\x0D\x0A" {
                if %*ENV<HTTP_TINY_DEBUG> {
                    note "> $_" for .lines;
                }
                $!handle.print($_);
            }

            self.write-header-lines: %headers;
        }

        method write-header-lines ( %headers ) {
            return unless %headers;

            my @headers = < host cache-control expect max-forwards pragma range te >;
            @headers.push: |%headers.keys.sort;

            my $buf = '';
            my SetHash $seen;
            for @headers -> $key {
                next if $seen{$key}++;
                my $v = %headers{$key} or next;

                my $field-name = lc $key;
                with HEADER-CASE{$field-name} -> $canonical {
                    $field-name = $canonical;
                }
                else {
                    s:g/ <|w> (\w) /$0.uc()/ given $field-name;
                }

                for $v.List -> $value {
                    $buf ~= "$field-name: $value\x0D\x0A";
                }
            }

            $buf ~= "\x0D\x0A";

            if %*ENV<HTTP_TINY_DEBUG> {
                note "> $_" for $buf.lines;
            }

            $!handle.print: $buf;
        }

        method write-request-body ( $content-length, &content ) {
            my $length = 0;
            while &content.() -> $blob {
                last unless $blob && $blob.bytes;
                $length += $blob.bytes;
                $!handle.write: $blob;
            }

            die "Content-Length mismatch (got: $length expected: $content-length"
                unless $length == $content-length;

            return;
        }

        method write-chunked-body ( &content, &trailer-callback ) {
            while &content.() -> $blob {
                last unless $blob && $blob.bytes;
                $!handle.write: "{ $blob.bytes.base: 16 }\r\n".encode;
                $!handle.write: $blob;
                $!handle.write: "\r\n".encode;
            }
            $!handle.write: "0\r\n\r\n".encode;

            self.write-header-lines: .() with &trailer-callback;
        }

        method get-response-header ( Blob[uint8] $chunk is rw, Bool :$trailer ) {
            $chunk .= new without $chunk;

            my $msg-body-pos;
            my Blob[uint8] $first-chunk .= new: $chunk;

            # Header can be longer than one chunk
            loop {
                last if $trailer && $first-chunk eq LINE-END;

                # Find the header/body separator in the chunk, which means
                # we can parse the header separately.
                $msg-body-pos = $first-chunk.&blob-search: HEADER-END;
                last if $msg-body-pos;

                my $blob = $!handle.recv: :bin;
                last unless $blob;

                $first-chunk ~= $blob;
            }

            # If the header would indicate that there won't
            # be any content there may not be a \r\n\r\n at
            # the end of the header.
            with $msg-body-pos {
                my $head = $first-chunk.subbuf: 0, $_ + 4;
                my $body = $first-chunk.subbuf:    $_ + 4;
                return $head, $body;
            }

            # Assume we have the whole header because if the server
            # didn't send it we're stuffed anyway
            return $first-chunk, Blob[uint8].new;
        }

        method read-response-header ( Blob[uint8] $header ) {
            my @header-lines = $header.decode('latin1').lines;

            my $status-line = try @header-lines.shift // '';

            $status-line ~~ /
                ^
                $<protocol> = [ 'HTTP/1.' [ 0 | 1 ] ] <[ \x09 \x20 ]>+
                $<status>   = [ \d ** 3 ]             <[ \x09 \x20 ]>+
                $<reason>   = <-[ \x0D \x0A ]>*
            / or die "Malformed Status-Line: $status-line";

            note "< $status-line" if %*ENV<HTTP_TINY_DEBUG>;

            return {
                protocol => ~$<protocol>,
                status   => +$<status>,
                reason   => ~$<reason>,
                headers  => self.read-header-lines(@header-lines),
                success  => $<status>.starts-with('2'),
            }
        }

        method read-header-lines (@lines) {
            die "Header lines exceed maximum allowed of $!max-header-lines"
                if @lines >= $!max-header-lines;

            my ( $val, %headers );
            for @lines {
                note "< $_" if %*ENV<HTTP_TINY_DEBUG>;

                when /
                    ^
                    $<key>   = <-[ \x00 .. \x1F \x7F : ]>+ ':' <[ \x09 \x20 ]>*
                    $<value> = <-[ \x0D \x0A ]>*
                / {
                    my $key   = lc $<key>;
                    my $value = ~$<value>;

                    if %headers{$key}:exists {
                        %headers{$key} .= Array;
                        %headers{$key}.push: $value;
                        $val := %headers{$key}.tail;

                    }
                    else {
                        %headers{$key} = $value;
                        $val := %headers{$key};
                    }
                }

                when /
                    ^
                    <[ \x09 \x20 ]>+
                    $<cont> = <-[ \x0D \x0A ]>*
                / {
                    die "Unexpected header continuation line" unless $val.defined;

                    if ~$<cont> -> $cont {
                        $val ~= ' ' if $val;
                        $val ~= $cont;
                    }
                }

                when .not {
                   last;
                }

                default {
                    die "Malformed header line: $_";
                }
            }

            return %headers;
        }

        method read-content ( &cb, Blob[uint8] $body is rw, %res --> Bool ) {
            my %headers = %res<headers>;

            # Multipart response
            with %headers<content-type>.first: {
                .defined
                && /
                    ^
                    'multipart/' .*
                    'boundary=' '"'? <( <-["]>+ )>
                /
            } {
                self!read-multipart-content( &cb, ~$/, $body );
                return True;
            }

            # Internal callbacks with arity greater than two are meaningless
            # past this point, so we simplify things.
            my &callback = &cb.arity == 1 ?? &cb !! &cb.assuming: *, Nil;

            # With content length
            with %res<headers><content-length> -> Int() $length {
                $body .= subbuf: 0, $length;

                my $bytes-read = $body.bytes;
                callback($body) if $bytes-read;

                while $bytes-read < $length {
                    my $read = min $length - $bytes-read, BUFFER-SIZE;
                    my $blob = $!handle.read: $read;
                    callback($blob);
                    $bytes-read += $blob.bytes;
                }

                return True;
            }

            # Chunked content
            my $encoding = %res<headers><transfer-encoding>;
            if $encoding.grep: { .defined && /chunked/ } {
                my $footer = self!read-chunked-content( &cb, $body );

                # Read trailing headers
                %res<headers>.append(
                    self.read-header-lines: $footer.decode('latin1').lines
                ) if $footer.bytes;

                return True;
            }

            # Otherwise read until EOF
            $body.&cb;
            while $!handle.read( BUFFER-SIZE ) -> $_ { .&cb }
            return False;
        }

        method !read-chunked-content ( &cb, Blob[uint8] $chunk is rw --> Blob[uint8] ) {
            # We carry on as long as we receive something.
            PARSE_CHUNK: loop {
                with $chunk.&blob-search: LINE-END {
                    my $size = $chunk.subbuf( 0, $_ ).decode;

                    # remove optional chunk extensions
                    $size = $size.subst: / ';' .* $ /, '';

                    # www.yahoo.com sends additional spaces (may be invalid)
                    $size .= trim-trailing;

                    $chunk = $chunk.subbuf: $_ + 2;
                    my $chunk-size = :16($size);

                    last PARSE_CHUNK if $chunk-size == 0;

                    while $chunk-size + 2 > $chunk.bytes {
                        $chunk ~= $!handle.recv:
                            $chunk-size + 2 - $chunk.bytes, :bin;
                    }

                    # Callback
                    $chunk.subbuf( 0, $chunk-size ).&cb;

                    $chunk = $chunk.subbuf: $chunk-size + 2;
                }
                else {
                    # XXX Reading 1 byte is inefficient code.
                    #
                    # But IO::Socket#read/IO::Socket#recv reads from socket
                    # until it fills the requested size.
                    #
                    # It can cause hang-up on socket reading.
                    my $byte = $!handle.recv: 1, :bin;
                    last PARSE_CHUNK unless $byte.elems;
                    $chunk ~= $byte;
                }
            }

            # Return all that is left, to parse possible trailers
            my ($trailer) = self.get-response-header: $chunk, :trailer;
            return $trailer;
        }

        method !read-multipart-content ( &cb, Str:D $boundary, Blob[uint8] $body is copy ) {
            # Callbacks for multipart responses will be called with two
            # arguments, so we need to normalise in case this one only
            # takes one.
            my &callback = &cb.arity == 1 ?? -> $blob, $ { $blob.&cb } !! &cb;
            my $end-of-stream = "--$boundary--".encode( 'ascii', replacement => '?' );

            loop {
                with $body.&blob-search: HEADER-END {
                    my $head = $body.subbuf: 0, $_ + 4;

                    my ( $marker, @header-lines ) = $head.decode('latin1').lines;
                    die "Invalid multipart boundary marker: $marker"
                        unless $marker eq "--$boundary";

                    my %headers = self.read-header-lines: @header-lines;
                    with %headers<content-range> {
                        die "Invalid Content-Range header: $_"
                            unless /
                                ^ 'bytes '
                                $<start> = \d+ '-' $<end> = \d*
                                '/'
                                $<total> = \d+
                                $
                            /;
                    }

                    # Start and end are zero-based, but total is one-based
                    my $length = ( $<end> // ( $<total> - 1 ) ) - +$<start> + 1;

                    # We make a distinction between the bytes in the current
                    # part and the bytes in the rest of the response body that
                    # belong to possible other parts
                    my $part = $body.subbuf: $head.bytes, $length;
                    $body .= subbuf: $head.bytes + $part.bytes;

                    my $read-bytes = $part.bytes;

                    # It's possible for the current part to be greater than
                    # the size of the current response chunk we have. If so,
                    # we need to continue reading until we have the entire
                    # part
                    loop {
                        callback( $part, %headers );
                        last if $read-bytes >= $length;

                        my $read = $!handle.read: BUFFER-SIZE;
                        die "Did not receive full byte range"
                            if !$read && $read-bytes < $length;

                        $read-bytes += $read.bytes;

                        # Including the bytes we have just read, we have more
                        # than the full part, so we save the rest in $body for
                        # further processing.
                        if $read-bytes > $length {
                            my $want = $read-bytes - $length;
                            $part = $read.subbuf: 0, *-$want - 1;
                            $body = $read.subbuf:    *-$want;
                        }
                        else {
                            $part = $read;
                        }
                    }

                    # Discard the CRLF preceding the next separator
                    $body .= subbuf: 2;
                }
                else {
                    # We have not read the header yet, need more
                    my $read = $!handle.read: BUFFER-SIZE or last;
                    $body ~= $read;
                }

                with $end-of-stream {
                    last if $body.subbuf( 0, .bytes ) eq $_;
                }
            }

            return;
        }
    }
}

=begin pod

=head2 NAME

HTTP::Tiny - A small, simple, correct HTTP/1.1 client

=head2 SYNOPSIS

=begin code

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

=end code

=head2 DESCRIPTION

This is a very simple but correct HTTP/1.1 client, designed for doing simple
requests without the overhead of a large framework like HTTP::UserAgent.

It is a Raku port of the Perl library of the same name. It supports
redirection, streaming requests and responses, multipart and URL-encoded
form uploads, and correctly handles multipart responses to ranged requests.

Cookie support is not yet implemented.

=head2 METHODS

Calling the C<new> method to construct an object is optional when using the
methods described in this section. When not doing so, C<new> will be called
automatically before executing the request, and the created object will be
discarded after the request is complete.

=head3 new

=begin code
method new (
          :%default-headers,
    Set() :%no-proxy,
    Str   :$http-proxy,
    Str   :$https-proxy,
    Str   :$agent = 'HTTP-Tiny/VERSION Raku',
    Int   :$max-redirect = 5,
    Bool  :$keep-alive,
    Bool  :$throw-exceptions,
) returns HTTP::Tiny
=end code

Creates a new HTTP::Tiny object. The following attributes are parameters:

=head4 default-headers

A Hash of default headers to apply to requests. Headers specified during the
call take precedence over the ones specified here.

=head4 agent

A Str to use as the value of the C<User-Agent> header. Defaults to
'HTTP-Tiny/$VERSION Raku'.

=head4 max-redirect

Maximum number of redirects allowed. Defaults to 5. Set to 0 to prevent
redirection.

=head4 keep-alive

Whether to re-use the last connection, if it is for the same scheme, host, and
port. Defaults to True.

=head4 throw-exceptions

When set to True, non-success HTTP responses will throw a C<X::HTTP::Tiny>
exception. The original error response Hash will be available as the result of
the C<.response> method of the exception.

=head4 proxy

URL of a generic proxy server for both HTTP and HTTPS connections.

Defaults to the value in the C<all_proxy> or C<ALL_PROXY> environment
variables (in that order). Set to the empty string to ignore variables set in
the environment.

=head4 no-proxy

Set of domain suffixes that should not be proxied. Any value that implements
the C<Set> method is allowed. A Str is also allowed, in which case it must be
a comma-separated list of suffixes that will be split, trimmed, and coerced to
a Set.

Defaults to the value in the C<no_proxy>, which will be treated like the Str
case described above.

=head4 http-proxy

URL of a proxy server for HTTP connections.

Defaults to the value in the C<http_proxy> or C<HTTP_PROXY> environment
variables, or to the value of the C<proxy> parameter described above (in that
order). Set to the empty string to ignore variables set in the environment.

=head4 https-proxy

URL of a proxy server for HTTPS connections.

Defaults to the value in the C<https_proxy> or C<HTTPS_PROXY> environment
variables, or to the value of the C<proxy> parameter described above (in that
order). Set to the empty string to ignore variables set in the environment.

=head3 delete

Shorthand method for calling C<request> with 'DELETE' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 get

Shorthand method for calling C<request> with 'GET' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 head

Shorthand method for calling C<request> with 'HEAD' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 options

Shorthand method for calling C<request> with 'OPTIONS' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 patch

Shorthand method for calling C<request> with 'PATCH' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 post

Shorthand method for calling C<request> with 'POST' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 put

Shorthand method for calling C<request> with 'PUT' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 trace

Shorthand method for calling C<request> with 'TRACE' as the method. See the
documentation for C<request> for full details on the supported parameters and
the return value.

=head3 request

=begin code
method request (
    Str $method,
    Str $url,
       :%headers,
       :$content,
       :&data-callback,
       :&trailer-callback,
) returns Hash
=end code

Executes an HTTP request of the given method type on the given URL. The URL
must have unsafe characters escaped and international domains encoded.
Valid HTTP methods are 'GET', 'DELETE', 'HEAD', 'OPTIONS', 'PATCH', 'POST',
'PUT', and 'TRACE', with their names being case sensitive as per the
HTTP/1.1 specification.

If the URL includes a "user:password" stanza, they will be used for
Basic-style authorisation headers. For example:

=begin code
$ua.request: 'GET', 'http://Aladdin:open sesame@example.com/';
=end code

If the "user:password" stanza contains reserved characters, they must
be percent-escaped:

=begin code
$ua.request: 'GET', 'http://john%40example.com:password@example.com/';
=end code

The C<Authorization> header generated from these data will not be included
in a redirected request. If you want to avoid this behaviour you can set the
value manually, in which case it will not be modified or ignored.

The remaining named parameters are detailed below.

=head4 %headers

A map of headers to include with the request. If the value is a List of strings,
the header will be output multiple times, once with each value in the array. The
headers specified in this parameter overwrite any default ones.

The C<Host> header is internally generated from the request URL in accordance
with RFC 2616. It is a fatal error to specify this header. Other headers may be
ignored or overwritten if necessary for transport compliance, but this will in
general be avoided.

=head4 $content

A value to use for the body of the request, which can be a Blob, a Str or
Numeric, a Hash, or a Callable, with each of these modifying the default
assumptions about the request.

If C<$content> is a Blob, the C<Content-Type> header will default to
C<application/octet-stream> and the contents of the Blob will be used as-is
as the body. The C<Content-Length> header will also default to the number
of bytes in the Blob.

If C<$content> is a Str or Numeric, it will be stringified by calling C<Str>
on it and internally encoded as UTF-8 and converted to a Blob. The
C<Content-Type> will in this case default to C<text/plain;charset=UTF-8>,
but handling will otherwise be as detailed above.

If C<$content> is a Hash, the default content type will depend on the values.
If any of the values is an IO::Path object it will be C<multipart/form-data>,
otherwise it will be C<application/x-www-form-urlencoded>.

If C<$content> is a Callable, it will be called iteratively to produce the
body of the request. When called, it must return a Blob with the next part
of the body until the body has been fully generated, in which case it must
return an empty Blob, or a Blob type object.

Note that these behaviours are the I<default> behaviours, and represent the
assumptions that will be made about the request based on the input.

When using a Callable, the C<Content-Type> will default to
C<application/octet-stream> and if no C<Content-Length> header has been set,
the C<Transfer-Encoding> will default to 'chunked', with each new part of the
body being sent in a separate chunk.

When using a Hash, its contents will be encoded depending on the value of the
C<Content-Type> header. Using IO::Path objects as values is only supported
with multipart form encoding. If a value is a IO::Path, IO::Handle, or
anything that supports the C<slurp> method, this will be called with the
C<:bin> argument to provide the value of that key, and the content type will
be set to C<application/octet-stream>. If using an IO::Path object, the
filename will be set to the result of calling C<basename>.

If no value is set, no C<Content-Type> or C<Content-Length> headers will be
generated.

=head4 &data-callback

The data callback takes a block of code that will be executed once with each
chunk of the response body. The callback will be introspected to determine
how many arguments it can receive, and will be called with up to three
arguments each time:

=item A Blob with the current encoded response chunk

=item A Hash with the current state of the response Hash

=item A Hash with the part headers (only for multipart responses)

This should allow customising the behaviour of the callback depending on the
response status or headers before receiving the full response body.

The callback must support at least the Blob argument. The other two are
optional. Not supporting any of these is an error.

=head4 &trailer-callback

When using a chunked transfer encoding, this callback will be called once after
the request body has been sent. It should return a Hash which will be used to
add trailing headers to the request.

=head4 The response Hash

The C<request> method returns a Hash with the response. The Hash will have the
following keys:

=defn success
A Bool that will be true if the response status code starts with a 2.

=defn url
The URL that provided the response as a Str. This will be the URL provided by
the caller unless there were redirections, in which case it will be the last
URL queried in the redirection chain.

=defn status
The HTTP status code of the response as an Int.

=defn reason
The response phrase as provided by the server.

=defn content
The body of the response as a Buf[uint8]. This key will be missing if the
response had no content or if a data callback was provided to consume the
body. HTTP::Tiny will never automatically decode a response body.

=defn headers
A Hash of header fields. All header fields will be normalised to be lower
case. If a header is repeated, the value will be a List with the received
values as Str objects. Otherwise, the value will be a Str. Header values
will be decoded using ISO-8859-1 as per
L<RFC 7230 § 3.2.4|https://tools.ietf.org/html/rfc7230#section-3.2.4>.

=defn protocol
The protocol of the response, such as 'HTTP/1.1' or 'HTTP/1.0'.

=defn redirects
If this key exists, it will hold a List of response Hash objects from the
encountered redirects in the order they occurred. This key will no exist if
no redirection took place.

If an exception is encountered during execution, the C<status> field will
be set to '599' and the C<content> field will hold the text of the exception.

=head3 mirror

=begin code
method mirror (
    Str  $url,
    IO() $file,
        :$content,
        :%headers,
        :&trailer-callback,
) returns Hash
=end code

Executes a C<GET> request for the URL and saves the response body to the
specified file. The URL must have unsafe characters escaped and
international domain names encoded. If the file already exists, the request
will include an C<If-Modified-Since> header with the modification timestamp
of the file if none has already been provided in the C<:%headers> parameter.
The parent directories of the file will not be automatically created.

The value of <$file> can be anything that implements an C<.IO> method.

The C<success> field of the response will be true if the status code is 2XX
or if the status code is 304 (unmodified).

If the file was modified and the server response includes a properly formatted
C<Last-Modified> header, the file modification time will be updated
accordingly. Note that currently this makes use of the C<touch> system
command, and will therefore not work if this command is not available.

=head3 can-ssl

=begin code
with HTTP::Tiny.can-ssl {
    # SSL support is available
}
else {
    note 'SSL support not available: ' ~ .exception.message;
}
=end code

Indicates if SSL support is available by checking for the correct version
of IO::Socket::SSL (greater than or equal to 0.0.2). It will either return
True if SSL support is available, or a Failure indicating why it isn't.

=head2 PROXY SUPPORT

HTTP::Tiny can proxy both HTTP and HTTPS requests. Only Basic proxy
authorization is supported and it must be provided as part of the proxy URL,
as in C<http://user:pass@proxy.example.com/>.

HTTP::Tiny supports the following proxy environment variables:

=item C<http_proxy> or C<HTTP_PROXY>

=item C<https_proxy> or C<HTTPS_PROXY>

=item C<all_proxy> or C<ALL_PROXY>

An HTTPS connection may be made via an HTTP proxy that supports the
C<CONNECT> method (cf. RFC 2817). If your proxy itself uses HTTPS, you can
not tunnel HTTPS over it.

Be warned that proxying an HTTPS connection opens you to the risk of a
man-in-the-middle attack by the proxy server.

The C<no_proxy> environment variable is supported in the format of a
comma-separated list of domain extensions proxy should not be used for.

Proxy arguments passed to C<new> will override their corresponding
environment variables.

=head2 LIMITATIONS

HTTP::Tiny aims to be I<conditionally compliant> with the
L<HTTP/1.1 specifications|http://www.w3.org/Protocols/>:

=item L<"Message Syntax and Routing" [RFC7230]|https://tools.ietf.org/html/rfc7230>

=item L<"Semantics and Content" [RFC7231]|https://tools.ietf.org/html/rfc7231>

=item L<"Conditional Requests" [RFC7232]|https://tools.ietf.org/html/rfc7232>

=item L<"Range Requests" [RFC7233]|https://tools.ietf.org/html/rfc7233>

=item L<"Caching" [RFC7234]|https://tools.ietf.org/html/rfc7234>

=item L<"Authentication" [RFC7235]|https://tools.ietf.org/html/rfc7235>

It aims to meet all "MUST" requirements of the specification, but only some
of the "SHOULD" requirements.

Some particular limitations of note include:

=begin item
HTTP::Tiny focuses on correct transport. Users are responsible for ensuring
that user-defined headers and content are compliant with the HTTP/1.1
specification.
=end item

=begin item
Users must ensure that URLs are properly escaped for unsafe characters and
that international domain names are properly encoded to ASCII.
=end item

=begin item
Redirection is very strict against the specification. Redirection is only
automatic for response codes 301, 302, 307 and 308 if the request method is
C<GET> or C<HEAD>. Response code 303 is always converted into a C<GET>
redirection, as mandated by the specification. There is no automatic support
for status 305 ("Use proxy") redirections.
=end item

=begin item
There is no provision for delaying a request body using an C<Expect> header.
Unexpected C<1XX> responses are silently ignored as per the specification.
=end item

=begin item
Only 'chunked' C<Transfer-Encoding> is supported.
=end item

=begin item
There is no support for a Request-URI of C<*> for the C<OPTIONS> request.
=end item

=begin item
Headers mentioned in the RFCs and some other, well-known headers are
generated with their canonical case. The order of headers is not
preserved: control headers are sent first, while the remainder are sent in
an unspecified order.
=end item

=begin item
No mitigations for L<httpoxy|https://httpoxy.org> have been implemented.
If you are using this library under CGI, you are on your own.
=end item

=head2 SEE ALSO

=head3 L<HTTP::UserAgent|https://modules.raku.org/dist/HTTP::UserAgent:github:github:sergot>

The de-facto blocking HTTP client for Raku, used by most applications. If a
feature you want is not supported in HTTP::Tiny, try using this distribution.
It is included in the Rakudo Star distribution, so chances are you already
have it.

That said, at the time of writing HTTP::UserAgent does not handle 1XX
responses, nor does it support chunked requests.

=head3 L<Cro::HTTP|https://modules.raku.org/dist/Cro::HTTP:cpan:JNTHN>

Part of the Cro family of libraries, it is written with asynchronous code as
its primary goal. Supports HTTP/2.0.

=head3 L<HTTP::Tinyish|https://modules.raku.org/dist/HTTP::Tinyish:cpan:SKAJI>

Another port from Perl, HTTP::Tinyish offers a similar interface to this
library while relying on an externally available C<curl> binary.

=head3 L<LibCurl|https://modules.raku.org/dist/LibCurl:cpan:CTILMES>

Raku bindings for libcurl. The bindings are fairly low-level, so they allow
for finer control than HTTP::Tinyish, but at the cost of a more complicated
interface.

=head3 L<LWP::Simple|https://modules.raku.org/dist/LWP::Simple:github:Cosimo%20Streppone>

An older an more barebones blocking HTTP client for Raku, preceding the
development of HTTP::UserAgent.

=head3 L<Net::HTTP|https://modules.raku.org/dist/Net::HTTP:github:ugexe>

A library providing the building blocks to write your own HTTP client.
Supports connection caching and should be thread safe.

Code is fairly low-level, so use in real-world scenarios might require
some effort until more progress is done in the implementation of classes
like Net::HTTP::Client.

=head2 AUTHOR

José Joaquín Atria <jjatria@cpan.org>

=head2 ACKNOWLEDGEMENTS

The code in this distribution is heavily inspired by that of L<the Perl library
of the same name|https://metacpan.org/pod/HTTP::Tiny>, written by Christian
Hansen and David Golden.

Some parts of the code have been adapted from existing solutions in the
HTTP::UserAgent codebase, which served as a reference on the use of Raku
toolbox.

=head2 COPYRIGHT AND LICENSE

Copyright 2020 José Joaquín Atria

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod
