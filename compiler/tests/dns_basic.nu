// dns_basic.nu — runtime §18c acceptance.
//
// Always-on: every probe is either a hostname that the C library
// resolves out of /etc/hosts ("localhost") or a numeric literal that
// bypasses the resolver entirely (127.0.0.1 / ::1). No external DNS
// is required. Hosts without "localhost" mapped (uncommon but legal)
// will see Err NetOther printed instead of a hard test failure.
//
// Sanity-check shape only — values like the exact loopback alias
// vary across /etc/nsswitch.conf configurations.

$ `stdlib/std/dns.nu`
$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ print_label_str s label s value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ print_label_int s label i value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : s txt ( nurl_str_int value )
    ( nurl_print txt )
    ( nurl_print `\n` )
}

@ print_label_bool s label b v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

// Walk a Vec[String] and free each element.
@ free_str_vec ( Vec String ) v → v {
    : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
    ( vec_free_with [String] v drop_str )
}

// Was "127.0.0.1" produced for localhost? Useful as a soft signal.
@ vec_contains_str ( Vec String ) v s needle → b {
    : i nlen ( nurl_str_len needle )
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        : ?String got ( vec_get [String] v k )
        ?? got {
            T elem → {
                : s ed ( string_data elem )
                ? & == ( nurl_str_len ed ) nlen == ( nurl_str_eq ed needle ) 1
                    { ^ T } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

@ main → i {
    // ── 1. Resolve "localhost" — expect ≥ 1 record. ─────────────
    : !( Vec String ) NetErr r1 ( dns_resolve `localhost` )
    ?? r1 {
        T addrs → {
            : i n ( vec_len [String] addrs )
            ( print_label_int `localhost_count` n )
            ( print_label_bool `localhost_has_v4` ( vec_contains_str addrs `127.0.0.1` ) )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `localhost_err` ( net_err_name e ) )
    }

    // ── 2. Resolve numeric literal — must succeed (bypasses DNS). ─
    : !( Vec String ) NetErr r2 ( dns_resolve `127.0.0.1` )
    ?? r2 {
        T addrs → {
            ( print_label_int `literal_v4_count` ( vec_len [String] addrs ) )
            ( print_label_bool `literal_v4_first` ( vec_contains_str addrs `127.0.0.1` ) )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `literal_v4_err` ( net_err_name e ) )
    }

    : !( Vec String ) NetErr r3 ( dns_resolve `::1` )
    ?? r3 {
        T addrs → {
            ( print_label_int `literal_v6_count` ( vec_len [String] addrs ) )
            ( print_label_bool `literal_v6_first` ( vec_contains_str addrs `::1` ) )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `literal_v6_err` ( net_err_name e ) )
    }

    // ── 3. resolve_port — verify ":<port>" suffix on every entry. ─
    : !( Vec String ) NetErr r4 ( dns_resolve_port `127.0.0.1` 8080 )
    ?? r4 {
        T addrs → {
            ( print_label_int `with_port_count` ( vec_len [String] addrs ) )
            ( print_label_bool `with_port_includes_8080`
                ( vec_contains_str addrs `127.0.0.1:8080` ) )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `with_port_err` ( net_err_name e ) )
    }

    : !( Vec String ) NetErr r5 ( dns_resolve_port `::1` 8080 )
    ?? r5 {
        T addrs → {
            ( print_label_int `v6_port_count` ( vec_len [String] addrs ) )
            ( print_label_bool `v6_port_bracketed`
                ( vec_contains_str addrs `[::1]:8080` ) )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `v6_port_err` ( net_err_name e ) )
    }

    // ── 4. Reverse lookup. Allowed outcomes: Some "<host>" OR None. ─
    : ?String rev ( dns_reverse `127.0.0.1` )
    ?? rev {
        T h → {
            ( print_label_str `reverse_127` ( string_data h ) )
            ( string_free h )
        }
        F → ( print_label_str `reverse_127` `NONE` )
    }

    // ── 5. Empty / bogus input must surface as Err, not crash. ─
    : !( Vec String ) NetErr rb ( dns_resolve `` )
    ?? rb {
        T addrs → {
            ( print_label_str `empty_in` `unexpected_ok` )
            ( free_str_vec addrs )
        }
        F e → ( print_label_str `empty_in_err` ( net_err_name e ) )
    }

    ^ 0
}
