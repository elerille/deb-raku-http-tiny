use Test;

sub EXPORT { Test::EXPORT::DEFAULT:: }

class Test::Handle does IO::Socket {
    has $.writer is rw = -> $ {;}
    has $.reader is rw = -> {;}

    method TWEAK ( :$response, Block :$writer ) {
        return unless $response;
        my @responses = $response.map: -> $src is copy {
            given $src {
                when IO::Path { $_ .= slurp: :bin;        proceed }
                when Str      { $_  = Blob.new: .encode;  proceed }
                when Blob     { $_  = Buf[uint8].new: $_;         }
            }
        }

        my @bodies = flat @responses [Z] Buf[uint8] xx @responses.elems;

        $!reader = -> $bytes { @bodies.shift // Buf[uint8] }
    }

    method read ( $bytes ) { $.reader.( $bytes ) }
    method recv ( Cool $bytes = Int, :$bin ) {
        my $ret = $.reader.( $bytes );
        return $ret.Str unless $bin;
        return $ret;
    }

    method write ( Blob $buf ) { $.writer.($buf) }
    method print ( Str(Cool) $str ) {
        $.writer.( $str.encode )
    }

    method close {}
}

class Response::Handle is Test::Handle {
    has $!handle;

    method TWEAK () {
        $.reader = -> $bytes { $!handle.read: |( $bytes if $bytes ) }
        $.writer = -> $data {
            return unless $data;
            with $data.decode.lines.head {
                when / 'HTTP/1.1' / {
                    my ( $method, $path ) = .split: /\s/;
                    $!handle = 't/res/'.IO
                        .child( lc $method )
                        .child($path)
                        .open;
                }
            }
        }
    }

    submethod DESTROY { $!handle.close }
}

class Request::Handle is Test::Handle {
    method new ( IO() :$out ) {
        self.bless:
            response => "HTTP/1.1 200 OK\r\n",
            writer   => -> $blob { $out.spurt: $blob, :append }
    }
}
