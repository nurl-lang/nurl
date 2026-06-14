// examples/nat.nu — gather this host's connection candidates and probe the
// NAT mapping type (TODO §7.4 Phase 1). On one UDP socket we discover:
//   • host candidate  — our routable local IP + the socket's port
//   • srflx candidate — the public endpoint a STUN server observed
// then query a SECOND STUN server and compare the reflexive endpoints to
// classify the NAT (cone → hole-punchable, symmetric → must relay).
//
//   ./nurl.sh examples/nat.nu
//
// Needs outbound UDP + DNS. Uses public STUN servers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/net/stun.nu`
$ `stdlib/net/nat.nu`

@ kind_name i k → s { ^ ? == k 0 `host ` ? == k 1 `srflx` `relay` }

// Build "<host>:<port>" without nurl_print_int (which forces a newline).
@ endpoint_str String host i port → String {
    : String s ( string_with_cap 48 )
    ( string_push_str s ( string_data host ) )
    ( string_push_char s 58 )
    ( string_push_int s port )
    ^ s
}

@ show_candidates ( Vec s ) cs → v {
    : i n ( vec_len [s] cs )
    ( nurl_print `candidates:\n` )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Candidate c # *Candidate pp
            : String ep ( endpoint_str . c host . c port )
            ( nurl_print `  [` ) ( nurl_print ( kind_name . c kind ) ) ( nurl_print `] ` )
            ( nurl_print ( string_data ep ) )
            ( nurl_print ? == . c family 2 `  (IPv6)\n` `  (IPv4)\n` )
            ( string_free ep )
        } {}
        = k + k 1
    }
}

@ type_name i t → s { ^ ? == t 1 `endpoint-independent (cone) — hole punch can work` ? == t 2 `symmetric / CGNAT — go straight to a relay` `unknown (STUN unreachable)` }

@ main → i {
    : !UdpSocket NetErr sr ( udp_bind_any )
    ?? sr {
        T sock → {
            // ── candidates ───────────────────────────────────────
            : ( Vec s ) cs ( nat_gather sock `stun.l.google.com` 19302 3000 )
            ( show_candidates cs )
            ( nat_candidates_free cs )

            // ── NAT-type probe (two distinct servers) ─────────────
            ( nurl_print `\nprobing NAT type …\n` )
            : i t ( nat_probe sock `stun.l.google.com` 19302 `stun.cloudflare.com` 3478 3000 )
            ( nurl_print `NAT type: ` ) ( nurl_print ( type_name t ) ) ( nurl_print `\n` )
            ( nurl_print ? ( nat_punchable t ) `→ attempt direct UDP hole punch\n` `→ relay path\n` )

            ( udp_close sock )
        }
        F e → ( nurl_print `bind failed\n` )
    }
    ^ 0
}
