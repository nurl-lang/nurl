// examples/stun.nu — discover this host's public (server-reflexive) UDP
// endpoint via a STUN server (TODO §7.4 Phase 1). The same socket the
// transport uses sends a Binding request; the server echoes back the
// address+port it saw — i.e. how peers across the NAT will reach us.
//
//   ./nurl.sh examples/stun.nu [stun_host] [stun_port]
// Defaults to a public STUN server.

$ `stdlib/core/string.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/stun.nu`

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `stun.l.google.com` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 19302

    : !UdpSocket NetErr sr ( udp_bind_any )
    ?? sr {
        T sock → {
            ( nurl_print `querying ` ) ( nurl_print ( string_data host ) )
            ( nurl_print `:` ) ( nurl_print_int port ) ( nurl_print ` …\n` )
            : ?StunAddr a ( stun_query sock ( string_data host ) port 3000 )
            ?? a {
                T sa → {
                    ( nurl_print `public endpoint: ` )
                    ( nurl_print ( string_data . sa host ) )
                    ( nurl_print `:` ) ( nurl_println_int . sa port )
                    ( stun_addr_free sa )
                }
                F → ( nurl_print `no STUN response (no internet / DNS / blocked)\n` )
            }
            ( udp_close sock )
        }
        F e → ( nurl_print `bind failed\n` )
    }
    ( string_free host )
    ^ 0
}
