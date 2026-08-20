// net_dnsclient.nu — offline test for stdlib/net/dnsclient.nu, the
// sans-IO stub resolver. Deterministic: queries are byte-compared to
// the RFC 1035 wire form, responses are hand-built — including the
// hostile ones, because a resolver parses bytes that arrive from a
// network the stack does not trust.
//
// The load-bearing cases:
//   * a compression-pointer LOOP must be an error, never a hang
//   * the TC bit must be an error (this stub does no TCP retry)
//   * a CNAME is followed only within the message, and only for the
//     name currently wanted
//   * record names compare case-insensitively (RFC 1035 §2.3.3)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/dnsclient.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

// Build a response header: id, flags, qd, an — trailing counts zero.
@ __hdr i id i flags i qd i an → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( bytes_push_u16_be v # u16 id )
    ( bytes_push_u16_be v # u16 flags )
    ( bytes_push_u16_be v # u16 qd )
    ( bytes_push_u16_be v # u16 an )
    ( bytes_push_u16_be v # u16 0 )
    ( bytes_push_u16_be v # u16 0 )
    ^ v
}

// Push "www.example.com"-style name as labels (no compression).
@ __push_name ( Vec u ) v s name → v {
    : i n ( nurl_str_len name )
    : ~ i start 0
    : ~ i k 0
    ~ <= k n {
        : ~ b cut == k n
        ? ! cut { ? == ( nurl_str_get name k ) 46 { = cut T } {} } {}
        ? cut {
            ( vec_push [u] v # u - k start )
            : ~ i j start
            ~ < j k { ( vec_push [u] v # u ( nurl_str_get name j ) ) = j + j 1 }
            = start + k 1
        } {}
        = k + k 1
    }
    ( vec_push [u] v # u 0 )
}

// Push question section for name, qtype A, class IN.
@ __push_q ( Vec u ) v s name → v {
    ( __push_name v name )
    ( bytes_push_u16_be v # u16 1 )
    ( bytes_push_u16_be v # u16 1 )
}

// Push one answer record: name (labels), type, rdata already encoded.
@ __push_rr ( Vec u ) v s name i rtype ( Vec u ) rdata → v {
    ( __push_name v name )
    ( bytes_push_u16_be v # u16 rtype )
    ( bytes_push_u16_be v # u16 1 )  // IN
    ( bytes_push_u32_be v # u32 60 )  // TTL
    ( bytes_push_u16_be v # u16 ( vec_len [u] rdata ) )
    : i n ( vec_len [u] rdata )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ?? ( vec_get [u] rdata k ) { T x → # i x F → 0 } ) = k + k 1 }
}

@ __a_rdata i ip → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( bytes_push_u32_be v # u32 ip )
    ^ v
}

@ err_of ! ( Vec i ) DnsErr r → s {
    ^ ?? r {
        T v → { ( vec_free [i] v ) `ok` }
        F e → ( dns_err_name e )
    }
}

@ main → i {
    // ── the question's wire form, byte-exact ────────────────────
    ?? ( dns_build_query 4660 `www.abc.io` ) {
        T q → {
            // 12 header + 1+3+1+3+1+2+1 name + 4 = 28
            ( pb `query length 28:        ` == ( vec_len [u] q ) 28 )
            ( pb `query id:               ` == ?? ( bytes_read_u16_be q 0 ) { T x → # i x F → 0 } 4660 )
            ( pb `query RD flag:          ` == ?? ( bytes_read_u16_be q 2 ) { T x → # i x F → 0 } 256 )
            ( pb `qname first label len:  ` == ?? ( vec_get [u] q 12 ) { T x → # i x F → 0 } 3 )
            ( pb `qtype A, class IN:      ` && == ?? ( bytes_read_u16_be q 24 ) { T x → # i x F → 0 } 1 == ?? ( bytes_read_u16_be q 26 ) { T x → # i x F → 0 } 1 )
            ( vec_free [u] q )
        }
        F e → { ( pb `query built:            ` F ) }
    }
    ( pb `empty name refused:     ` ?? ( dns_build_query 1 `` ) { T v → { ( vec_free [u] v ) F } F e → T } )
    ( pb `double dot refused:     ` ?? ( dns_build_query 1 `a..b` ) { T v → { ( vec_free [u] v ) F } F e → T } )

    // ── a clean single-A response ───────────────────────────────
    : ( Vec u ) r1 ( __hdr 7 33152 1 1 )  // QR|RD|RA, rcode 0
    ( __push_q r1 `www.abc.io` )
    : ( Vec u ) a1 ( __a_rdata 16909060 )  // 1.2.3.4
    ( __push_rr r1 `www.abc.io` 1 a1 )
    ( vec_free [u] a1 )
    ?? ( dns_parse_a r1 7 `www.abc.io` ) {
        T v → {
            ( pb `one A answer:           ` && == ( vec_len [i] v ) 1 == ?? ( vec_get [i] v 0 ) { T x → x F → 0 } 16909060 )
            ( vec_free [i] v )
        }
        F e → { ( pb `one A answer:           ` F ) }
    }
    // case-insensitive record names
    ?? ( dns_parse_a r1 7 `WWW.ABC.IO` ) {
        T v → { ( pb `case-folded match:      ` == ( vec_len [i] v ) 1 ) ( vec_free [i] v ) }
        F e → { ( pb `case-folded match:      ` F ) }
    }
    ( pb `wrong id:               ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r1 8 `www.abc.io` ) ) `wrong-id` ) )
    ( vec_free [u] r1 )

    // ── CNAME then A, in one message ────────────────────────────
    : ( Vec u ) r2 ( __hdr 9 33152 1 2 )
    ( __push_q r2 `www.abc.io` )
    : ( Vec u ) cn ( vec_new [u] )
    ( __push_name cn `real.abc.io` )
    ( __push_rr r2 `www.abc.io` 5 cn )
    ( vec_free [u] cn )
    : ( Vec u ) a2 ( __a_rdata 84281096 )  // 5.6.7.8
    ( __push_rr r2 `real.abc.io` 1 a2 )
    ( vec_free [u] a2 )
    ?? ( dns_parse_a r2 9 `www.abc.io` ) {
        T v → {
            ( pb `CNAME chased to A:      ` && == ( vec_len [i] v ) 1 == ?? ( vec_get [i] v 0 ) { T x → x F → 0 } 84281096 )
            ( vec_free [i] v )
        }
        F e → { ( pb `CNAME chased to A:      ` F ) }
    }
    ( vec_free [u] r2 )

    // ── an A for some OTHER name must not count ─────────────────
    : ( Vec u ) r3 ( __hdr 11 33152 1 1 )
    ( __push_q r3 `www.abc.io` )
    : ( Vec u ) a3 ( __a_rdata 167837962 )
    ( __push_rr r3 `evil.abc.io` 1 a3 )
    ( vec_free [u] a3 )
    ( pb `stray A ignored:        ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r3 11 `www.abc.io` ) ) `no-answer` ) )
    ( vec_free [u] r3 )

    // ── envelope errors ─────────────────────────────────────────
    : ( Vec u ) r4 ( __hdr 13 33664 1 0 )  // TC set (0x8200)
    ( __push_q r4 `www.abc.io` )
    ( pb `TC bit is an error:     ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r4 13 `www.abc.io` ) ) `truncated` ) )
    ( vec_free [u] r4 )
    : ( Vec u ) r5 ( __hdr 15 33155 1 0 )  // rcode 3 NXDOMAIN
    ( __push_q r5 `www.abc.io` )
    ( pb `NXDOMAIN reported:      ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r5 15 `www.abc.io` ) ) `server-error` ) )
    ( vec_free [u] r5 )
    : ( Vec u ) r6 ( __hdr 17 256 1 0 )  // QR clear: a question, not an answer
    ( __push_q r6 `www.abc.io` )
    ( pb `question refused:       ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r6 17 `www.abc.io` ) ) `not-a-response` ) )
    ( vec_free [u] r6 )
    : ( Vec u ) r7 ( vec_new [u] )
    ( vec_push [u] r7 # u 0 )
    ( pb `short response:         ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r7 0 `www.abc.io` ) ) `short` ) )
    ( vec_free [u] r7 )

    // ── the hostile ones ────────────────────────────────────────
    // A compression pointer that points at itself: the name reader
    // must run out of hop budget, not out of patience.
    : ( Vec u ) r8 ( __hdr 19 33152 1 1 )
    ( __push_q r8 `www.abc.io` )
    : i loop_at ( vec_len [u] r8 )
    ( vec_push [u] r8 # u 192 )  // pointer …
    ( vec_push [u] r8 # u loop_at )  // … at itself (offset < 255 here)
    ( bytes_push_u16_be r8 # u16 1 )  // type A
    ( bytes_push_u16_be r8 # u16 1 )  // class IN
    ( bytes_push_u32_be r8 # u32 60 )  // TTL
    ( bytes_push_u16_be r8 # u16 4 )
    ( bytes_push_u32_be r8 # u32 1 )
    ( pb `pointer loop is error:  ` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r8 19 `www.abc.io` ) ) `bad-label` ) )
    ( vec_free [u] r8 )
    // An rdlen that runs past the end of the message.
    : ( Vec u ) r9 ( __hdr 21 33152 1 1 )
    ( __push_q r9 `www.abc.io` )
    ( __push_name r9 `www.abc.io` )
    ( bytes_push_u16_be r9 # u16 1 )
    ( bytes_push_u16_be r9 # u16 1 )
    ( bytes_push_u32_be r9 # u32 60 )
    ( bytes_push_u16_be r9 # u16 400 )  // rdlen far past the end
    ( pb `overlong rdata is error:` != 0 ( nurl_str_eq ( err_of ( dns_parse_a r9 21 `www.abc.io` ) ) `bad-label` ) )
    ( vec_free [u] r9 )

    ( nurl_print `net_dnsclient done\n` )
    ^ 0
}
