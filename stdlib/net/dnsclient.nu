// stdlib/net/dnsclient.nu — the stub resolver, as pure logic (plan A1a).
//
// Builds an A-record query and reads the answer back out of the raw
// response bytes. SANS-IO like every module in net/: no sockets, no
// clocks, no FFI — the caller owns the UDP round trip (the unikernel's
// socket shim sends the query to the DHCP-learned server; a test hands
// in canned bytes). What this module owns is exactly the two things
// that can be gotten wrong offline: the wire encoding of a question,
// and the defensive walk of a response that arrived from a network
// this stack does not trust.
//
// Scope, stated (the plan's stub-resolver limitations):
//   - A records over UDP. No AAAA (the stack has no IPv6), no MX/TXT.
//   - A truncated response (TC bit) is an ERROR, not a TCP retry.
//   - CNAME chains are followed WITHIN the one response message, up to
//     a small bound — a resolver that answers "www.x is an alias and I
//     did not include the address" answers nothing.
//   - Compression pointers are followed with a hop budget, because a
//     pointer loop in a hostile response must be an error, not a hang
//     (the same rule net_tcp_fuzz pins for TCP options).
//
// Every reader here treats the response as HOSTILE: lengths are
// checked before every read, pointers are bounded, and label lengths
// above 63 (the wire maximum) are refused.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

: | DnsErr {
    DnsBadName  // the queried name cannot be encoded (empty / too long)
    DnsShort  // response ends before a field it promised
    DnsWrongId  // response id does not match the query's
    DnsNotResponse  // QR bit says this is a question, not an answer
    DnsTruncated  // TC bit — the answer did not fit UDP (no TCP retry in v1)
    DnsRcode  // server said NXDOMAIN / SERVFAIL / …
    DnsBadLabel  // label length above 63, or a compression-pointer loop
    DnsNoAnswer  // a well-formed response with no usable A record
}

@ dns_err_name DnsErr e → s {
    ^ ?? e {
        DnsBadName → `bad-name`
        DnsShort → `short`
        DnsWrongId → `wrong-id`
        DnsNotResponse → `not-a-response`
        DnsTruncated → `truncated`
        DnsRcode → `server-error`
        DnsBadLabel → `bad-label`
        DnsNoAnswer → `no-answer`
    }
}

// qtype/qclass constants — the two this module speaks.
@ dns_qtype_a → i { ^ 1 }

@ dns_qtype_cname → i { ^ 5 }

@ dns_class_in → i { ^ 1 }

// ── the question ────────────────────────────────────────────────

// Encode `name` ("www.example.com") as DNS labels into `out`.
// Refuses an empty name, an empty label (".." or a leading/trailing
// dot), a label over 63 bytes, or a total encoding over 255.
@ __dns_push_qname ( Vec u ) out s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n 253 { ^ F } {}
    : ~ i start 0
    : ~ i k 0
    ~ <= k n {
        : b at_end == k n
        : ~ b dot F
        ? ! at_end { ? == ( nurl_str_get name k ) 46 { = dot T } {} } {}
        ? | at_end dot {
            : i llen - k start
            ? | == llen 0 > llen 63 { ^ F } {}
            ( vec_push [u] out # u llen )
            : ~ i j start
            ~ < j k { ( vec_push [u] out # u ( nurl_str_get name j ) ) = j + j 1 }
            = start + k 1
        } {}
        = k + k 1
    }
    ( vec_push [u] out # u 0 )
    ^ T
}

// One A-record question, RD (recursion desired) set — this is a STUB
// resolver: the server does the walking, exactly what a DHCP-announced
// resolver is for.
@ dns_build_query i id s name → !( Vec u ) DnsErr {
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_push_u16_be out # u16 id )
    ( bytes_push_u16_be out # u16 256 )  // flags: RD
    ( bytes_push_u16_be out # u16 1 )  // QDCOUNT
    ( bytes_push_u16_be out # u16 0 )  // ANCOUNT
    ( bytes_push_u16_be out # u16 0 )  // NSCOUNT
    ( bytes_push_u16_be out # u16 0 )  // ARCOUNT
    ? ! ( __dns_push_qname out name ) {
        ( vec_free [u] out )
        ^ @ !( Vec u ) DnsErr { F # DnsErr DnsBadName }
    } {}
    ( bytes_push_u16_be out # u16 ( dns_qtype_a ) )
    ( bytes_push_u16_be out # u16 ( dns_class_in ) )
    ^ @ !( Vec u ) DnsErr { T out }
}

// ── the response ────────────────────────────────────────────────

@ __dns_u16 ( Vec u ) v i off → i {
    ^ ?? ( bytes_read_u16_be v off ) { T x → # i x F → -1 }
}

// Skip a (possibly compressed) name starting at `off`; return the
// offset of the first byte AFTER it in the record stream, or -1.
// A pointer ends the in-stream name (2 bytes), whatever it points at.
@ __dns_skip_name ( Vec u ) v i off → i {
    : i n ( vec_len [u] v )
    : ~ i k off
    : ~ i out -1
    : ~ b run T
    ~ run {
        ? >= k n { = run F } {
            : i len ?? ( vec_get [u] v k ) { T x → # i x F → 0 }
            ? == len 0 { = out + k 1 = run F } {
                ? == & len 192 192 { = out + k 2 = run F } {
                    ? > len 63 { = run F } {
                        = k + + k 1 len
                    }
                }
            }
        }
    }
    ? > out n { ^ -1 } {}
    ^ out
}

// Decode the name at `off` into lowercase text, following compression
// pointers with a hop budget. Returns "" on any malformation.
@ __dns_read_name ( Vec u ) v i off → String {
    : String out ( string_new )
    : i n ( vec_len [u] v )
    : ~ i k off
    : ~ i hops 0
    : ~ b run T
    : ~ b bad F
    ~ run {
        ? | >= k n > hops 40 { = bad T = run F } {
            : i len ?? ( vec_get [u] v k ) { T x → # i x F → 0 }
            ? == len 0 { = run F } {
                ? == & len 192 192 {
                    // pointer: 14-bit offset — bounded hops, so a loop
                    // is an error rather than forever
                    ? >= + k 1 n { = bad T = run F } {
                        : i lo ?? ( vec_get [u] v + k 1 ) { T x → # i x F → 0 }
                        = k | << & len 63 8 lo
                        = hops + hops 1
                    }
                } {
                    ? | > len 63 >= + k len n { = bad T = run F } {
                        ? > ( string_len out ) 0 { ( string_push_char out 46 ) } {}
                        : ~ i j 1
                        ~ <= j len {
                            : ~ i c ?? ( vec_get [u] v + k j ) { T x → # i x F → 0 }
                            // names compare case-insensitively (RFC 1035
                            // §2.3.3); fold here so callers use nurl_str_eq
                            ? && >= c 65 <= c 90 { = c + c 32 } {}
                            ( string_push_char out c )
                            = j + j 1
                        }
                        = k + + k 1 len
                        ? > ( string_len out ) 253 { = bad T = run F } {}
                    }
                }
            }
        }
    }
    ? bad { ( string_free out ) ^ ( string_new ) } {}
    ^ out
}

// Parse a response to `dns_build_query id name`: verify the envelope,
// then walk the answer records collecting A addresses for `name`,
// following CNAMEs that appear in the same message. Returns the
// addresses as u32s (host order), in answer order.
@ dns_parse_a ( Vec u ) resp i id s qname → !( Vec i ) DnsErr {
    : i n ( vec_len [u] resp )
    ? < n 12 { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsShort } } {}
    ? != ( __dns_u16 resp 0 ) id { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsWrongId } } {}
    : i flags ( __dns_u16 resp 2 )
    ? == & flags 32768 0 { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsNotResponse } } {}
    ? != & flags 512 0 { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsTruncated } } {}
    ? != & flags 15 0 { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsRcode } } {}
    : i qd ( __dns_u16 resp 4 )
    : i an ( __dns_u16 resp 6 )
    // past the question section
    : ~ i off 12
    : ~ i qi 0
    : ~ b bad F
    ~ && < qi qd ! bad {
        = off ( __dns_skip_name resp off )
        ? < off 0 { = bad T } { = off + off 4 }
        = qi + qi 1
    }
    ? | bad > off n { ^ @ !( Vec i ) DnsErr { F # DnsErr DnsShort } } {}
    // The name we are currently hunting: starts as the query name,
    // reassigned when a CNAME for it appears. Owned copy per hop.
    : ~ String want ( string_new )
    {
        // lowercase the query name once, so every comparison below is
        // the case-folded one __dns_read_name already produces
        : i qn ( nurl_str_len qname )
        : ~ i qk 0
        ~ < qk qn {
            : ~ i c ( nurl_str_get qname qk )
            ? && >= c 65 <= c 90 { = c + c 32 } {}
            ( string_push_char want c )
            = qk + qk 1
        }
    }
    : ( Vec i ) out ( vec_new [i] )
    // Two passes over the answers per CNAME hop would be quadratic in
    // a hostile message; one pass suffices because a conforming
    // response lists the CNAME before the records it aliases to —
    // and a message that does not simply answers DnsNoAnswer.
    : ~ i ai 0
    : ~ b fail F
    ~ && < ai an ! fail {
        : String rname ( __dns_read_name resp off )
        ? == ( string_len rname ) 0 { ( string_free rname ) = fail T } {
            = off ( __dns_skip_name resp off )
            ? | < off 0 > + off 10 n { ( string_free rname ) = fail T } {
                : i rtype ( __dns_u16 resp off )
                : i rdlen ( __dns_u16 resp + off 8 )
                : i rdoff + off 10
                = off + rdoff rdlen
                ? | < rdlen 0 > off n { ( string_free rname ) = fail T } {
                    ? ( nurl_str_eq ( string_data rname ) ( string_data want ) ) {
                        ? && == rtype ( dns_qtype_a ) == rdlen 4 {
                            ( vec_push [i] out ?? ( bytes_read_u32_be resp rdoff ) { T x → # i x F → 0 } )
                        } {
                            ? == rtype ( dns_qtype_cname ) {
                                : String target ( __dns_read_name resp rdoff )
                                ? > ( string_len target ) 0 {
                                    ( string_free want )
                                    = want target
                                } { ( string_free target ) }
                            } {}
                        }
                    } {}
                    ( string_free rname )
                }
            }
        }
        = ai + ai 1
    }
    ( string_free want )
    ? fail {
        ( vec_free [i] out )
        ^ @ !( Vec i ) DnsErr { F # DnsErr DnsBadLabel }
    } {}
    ? == ( vec_len [i] out ) 0 {
        ( vec_free [i] out )
        ^ @ !( Vec i ) DnsErr { F # DnsErr DnsNoAnswer }
    } {}
    ^ @ !( Vec i ) DnsErr { T out }
}
