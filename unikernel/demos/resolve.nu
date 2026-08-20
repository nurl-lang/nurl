// unikernel/demos/resolve.nu — name resolution on a machine with no
// operating system and no /etc/resolv.conf.
//
// The resolver is the network's own: DHCP option 6, or a `dns=ip[:port]`
// key on the kernel command line (the same host-states-a-fact contract
// as wallclock=). The query goes out over the pure UDP stack through
// net/dnsclient.nu — sans-IO parse and build, socket shim owns the
// round trip — and the answer comes back through the very same
// `dns_resolve` a hosted NURL program calls.
//
// argv[0] is the NAME to resolve; the gate runs a scripted DNS server
// on the host, so the answer is deterministic and the test needs no
// internet.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/dns.nu`
$ `stdlib/ext/env.nu`

@ main → i {
    ? < ( env_args_count ) 2 {
        ( nurl_print `usage: resolve <name>\n` )
        ^ 2
    } {}
    : String name ( env_arg 1 )
    ( nurl_print `resolving ` )
    ( nurl_print ( string_data name ) )
    ( nurl_print `\n` )
    : ~ i rc 0
    ?? ( dns_resolve ( string_data name ) ) {
        T ips → {
            : i n ( vec_len [String] ips )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] ips k ) {
                    T ip → { ( nurl_print `answer ` ) ( nurl_print ( string_data ip ) ) ( nurl_print `\n` ) }
                    F → {}
                }
                = k + k 1
            }
            : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
            ( vec_free_with [String] ips drop_str )
        }
        F e → {
            ( nurl_print `resolve failed\n` )
            = rc 1
        }
    }
    ( string_free name )
    ^ rc
}
