// nat_codec.nu — offline test for stdlib/net/nat.nu. Deterministic, no
// network: exercises the punch PING/PONG codec, the NAT-type classifier
// (same vs differing reflexive endpoints), and the address-string helpers
// the host-candidate path relies on.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/stun.nu`
$ `stdlib/net/nat.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mk_token → ( Vec u ) {
    : ( Vec u ) t ( vec_new [u] )
    : ~ i k 0 ~ < k 8 { ( vec_push [u] t # u + 16 k ) = k + k 1 }  // 0x10..0x17
    ^ t
}

@ sa s host i port → ?StunAddr { ^ @ ?StunAddr { T @ StunAddr { ( string_from host ) port 1 } } }

@ main → i {
    // ── punch codec round trip ───────────────────────────────────
    : ( Vec u ) tok ( mk_token )
    : ( Vec u ) ping ( nat_punch_build ( punch_ping ) tok )
    : ( Vec u ) pong ( nat_punch_build ( punch_pong ) tok )
    ( nurl_print `ping len: ` ) ( nurl_print_int ( vec_len [u] ping ) ) ( nurl_print `\n` )  // 4+1+8
    ( pb `ping is punch: ` ( nat_is_punch ping ) )
    ( pb `pong is punch: ` ( nat_is_punch pong ) )

    : ?PunchMsg pm ( nat_punch_parse ping )
    ?? pm {
        T m → {
            ( pb `parsed kind=ping: ` == . m kind ( punch_ping ) )
            ( pb `token preserved: ` == ?? ( vec_get [u] . m token 3 ) { T x → # i x F → -1 } 19 )  // 0x13
            ( punch_msg_free m )
        }
        F → ( nurl_print `punch parse failed\n` )
    }

    // a non-punch datagram is rejected
    : ( Vec u ) junk ( vec_new [u] )
    : ~ i j 0 ~ < j 6 { ( vec_push [u] junk # u 0 ) = j + j 1 }
    ( pb `junk rejected: ` ! ( nat_is_punch junk ) )

    // ── NAT-type classifier ──────────────────────────────────────
    : ?StunAddr a1 ( sa `203.0.113.5` 40000 )
    : ?StunAddr b1 ( sa `203.0.113.5` 40000 )
    ( pb `same endpoint → independent: ` == ( nat_classify a1 b1 ) ( nat_type_independent ) )
    ( pb `independent is punchable: ` ( nat_punchable ( nat_classify a1 b1 ) ) )

    : ?StunAddr a2 ( sa `203.0.113.5` 40000 )
    : ?StunAddr b2 ( sa `203.0.113.5` 50001 )
    ( pb `differing port → symmetric: ` == ( nat_classify a2 b2 ) ( nat_type_symmetric ) )
    ( pb `symmetric NOT punchable: ` ! ( nat_punchable ( nat_classify a2 b2 ) ) )

    : ?StunAddr none @ ?StunAddr { F # StunAddr 0 }
    ( pb `missing → unknown: ` == ( nat_classify a1 none ) ( nat_type_unknown ) )

    ?? a1 { T x → ( stun_addr_free x ) F → {} }
    ?? b1 { T x → ( stun_addr_free x ) F → {} }
    ?? a2 { T x → ( stun_addr_free x ) F → {} }
    ?? b2 { T x → ( stun_addr_free x ) F → {} }

    // ── address-string helpers ───────────────────────────────────
    : String v4 ( string_from `192.168.1.5:55000` )
    : String h4 ( __addr_host v4 )
    ( pb `v4 host parsed: ` & != 0 ( nurl_str_eq ( string_data h4 ) `192.168.1.5` ) == ( __addr_port v4 ) 55000 )
    ( pb `v4 family: ` == ( __ip_family h4 ) 1 )

    : String v6 ( string_from `[2001:db8::1]:9999` )
    : String h6 ( __addr_host v6 )
    ( pb `v6 host parsed: ` & != 0 ( nurl_str_eq ( string_data h6 ) `2001:db8::1` ) == ( __addr_port v6 ) 9999 )
    ( pb `v6 family: ` == ( __ip_family h6 ) 2 )

    ( string_free v4 ) ( string_free h4 ) ( string_free v6 ) ( string_free h6 )
    ( vec_free [u] tok ) ( vec_free [u] ping ) ( vec_free [u] pong ) ( vec_free [u] junk )
    ^ 0
}
