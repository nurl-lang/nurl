// stdlib/net/tcpseg.nu — TCP segment codec + sequence arithmetic.
//
// PURE. Split out from the connection state machine (net/tcp.nu) on
// purpose: the wire format and the sequence-number algebra are the two
// pieces that must be *provably* right before any state machine built
// on them can be trusted, and they are testable exhaustively on their
// own.
//
// SEQUENCE ARITHMETIC IS THE SUBTLE PART
//
// TCP sequence numbers live in a 32-bit space that wraps. "Is this
// segment newer?" is therefore NOT `a < b` — after a wrap, the newer
// number is numerically smaller. RFC 1323 §4.II states the rule: work
// with the *signed* 32-bit difference, so ordering is defined over the
// half-space (2^31) and wraps correctly.
//
// A stack that compares raw magnitudes works perfectly for hours and
// then, exactly once per 4 GB transferred, silently discards live data
// or accepts an ancient duplicate. That is the archetypal "flaky
// network" bug, and it is entirely avoidable by never writing a bare
// comparison on a sequence number.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`

// ── flags ────────────────────────────────────────────────────────

@ tcp_fin → i { ^ 1 }

@ tcp_syn → i { ^ 2 }

@ tcp_rst → i { ^ 4 }

@ tcp_psh → i { ^ 8 }

@ tcp_ack → i { ^ 16 }

@ tcp_urg → i { ^ 32 }

@ tcp_min_hdr → i { ^ 20 }

// The largest segment we will ever emit or accept as an MSS, derived
// from the Ethernet MTU: 1500 - 20 (IP) - 20 (TCP).
@ tcp_default_mss → i { ^ 1460 }

// A peer that offers no MSS option gets RFC 1122's default of 536.
@ tcp_fallback_mss → i { ^ 536 }

// ── 32-bit sequence arithmetic ───────────────────────────────────

@ seq_mask → i { ^ 4294967295 }

@ seq_add i a i b → i { ^ & + a b 4294967295 }

@ seq_sub i a i b → i { ^ & - a b 4294967295 }

// The signed 32-bit difference a - b. Everything else is built on it.
@ seq_diff i a i b → i {
    : i d & - a b 4294967295
    ^ ? >= d 2147483648 - d 4294967296 d
}

@ seq_lt i a i b → b { ^ < ( seq_diff a b ) 0 }

@ seq_leq i a i b → b { ^ <= ( seq_diff a b ) 0 }

@ seq_gt i a i b → b { ^ > ( seq_diff a b ) 0 }

@ seq_geq i a i b → b { ^ >= ( seq_diff a b ) 0 }

// Is `s` inside the half-open window [start, start+len)?
@ seq_in_window i s i start i len → b {
    ? == len 0 { ^ F } {}
    ^ && ( seq_geq s start ) ( seq_lt s ( seq_add start len ) )
}

// ── segment ──────────────────────────────────────────────────────

: TcpSeg {
    i src_port
    i dst_port
    i seq
    i ack
    i data_off  // header length in BYTES
    i flags
    i window  // as carried, BEFORE window-scale is applied
    i urgent
    i mss  // from options, 0 if absent
    i wscale  // from options, -1 if absent (distinct from a scale of 0)
    b sack_permitted
    i payload_off
    i payload_len
    b valid
}

@ __seg_bad → TcpSeg { ^ @ TcpSeg { 0 0 0 0 0 0 0 0 0 -1 F 0 0 F } }

// Parse a TCP segment, verifying the checksum against the enclosing
// IPv4 addresses. `len` is the TCP length from the IP header — never
// the frame length (see net/ipv4.nu on Ethernet padding).
@ tcpseg_parse ( Vec u ) buf i off i len i src_ip i dst_ip → TcpSeg {
    ? < len 20 { ^ ( __seg_bad ) } {}
    : i doff * >> ?? ( vec_get [u] buf + off 12 ) { T x → # i x F → 0 } 4 4
    ? || < doff 20 > doff len { ^ ( __seg_bad ) } {}
    : i s ( inet_sum_add ( ip4_pseudo_sum src_ip dst_ip ( ip_proto_tcp ) len ) buf off len )
    ? != ( inet_fold s ) 65535 { ^ ( __seg_bad ) } {}
    // ── options ──
    : ~ i mss 0
    : ~ i wscale -1
    : ~ b sack_ok F
    : ~ i k 20
    : ~ b done F
    ~ && ! done < k doff {
        : i kind ?? ( vec_get [u] buf + off k ) { T x → # i x F → 0 }
        ? == kind 0 { = done T } {
            ? == kind 1 { = k + k 1 } {
                ? >= + k 2 doff { = done T } {
                    : i olen ?? ( vec_get [u] buf + off + k 1 ) { T x → # i x F → 0 }
                    // A length < 2 would not advance — that is an
                    // infinite loop on hostile input, so stop.
                    ? || < olen 2 > + k olen doff { = done T } {
                        ? && == kind 2 == olen 4 {
                            = mss ?? ( bytes_read_u16_be buf + off + k 2 ) { T x → # i x F → 0 }
                        } {}
                        ? && == kind 3 == olen 3 {
                            : i sh ?? ( vec_get [u] buf + off + k 2 ) { T x → # i x F → 0 }
                            // RFC 7323 §2.3: a shift above 14 is
                            // clamped, not honoured.
                            = wscale ? > sh 14 14 sh
                        } {}
                        ? && == kind 4 == olen 2 { = sack_ok T } {}
                        = k + k olen
                    }
                }
            }
        }
    }
    ^ @ TcpSeg {
        ?? ( bytes_read_u16_be buf off ) { T x → # i x F → 0 }
        ?? ( bytes_read_u16_be buf + off 2 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 4 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 8 ) { T x → # i x F → 0 }
        doff
        & ?? ( vec_get [u] buf + off 13 ) { T x → # i x F → 0 } 63
        ?? ( bytes_read_u16_be buf + off 14 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u16_be buf + off 18 ) { T x → # i x F → 0 }
        mss
        wscale
        sack_ok
        + off doff
        - len doff
        T
    }
}

// How much sequence space a segment occupies: payload plus one for
// each of SYN and FIN. This is the quantity every ACK and window
// calculation is expressed in, so it gets a name rather than being
// open-coded at each site.
@ tcpseg_seq_len TcpSeg s → i {
    : ~ i n . s payload_len
    ? == & . s flags 2 2 { = n + n 1 } {}
    ? == & . s flags 1 1 { = n + n 1 } {}
    ^ n
}

// Append a TCP segment with a correct checksum. Options are emitted
// only on SYN segments, which is where they are meaningful.
@ tcpseg_push ( Vec u ) out i src_ip i dst_ip i src_port i dst_port i seq i ack i flags i window i mss i wscale ( Vec u ) payload i pay_off i pay_len → v {
    : i start ( vec_len [u] out )
    : b is_syn == & flags 2 2
    // options: MSS (4) + wscale (3) + 1 pad = 8 bytes on SYN
    : i optlen ? is_syn 8 0
    : i doff + 20 optlen
    ( bytes_push_u16_be out # u16 & src_port 65535 )
    ( bytes_push_u16_be out # u16 & dst_port 65535 )
    ( bytes_push_u32_be out # u32 & seq 4294967295 )
    ( bytes_push_u32_be out # u32 & ack 4294967295 )
    ( vec_push [u] out # u << / doff 4 4 )
    ( vec_push [u] out # u & flags 63 )
    ( bytes_push_u16_be out # u16 & window 65535 )
    ( bytes_push_u16_be out # u16 0 )  // checksum placeholder
    ( bytes_push_u16_be out # u16 0 )  // urgent pointer
    ? is_syn {
        ( vec_push [u] out # u 2 ) ( vec_push [u] out # u 4 )
        ( bytes_push_u16_be out # u16 & ? > mss 0 mss ( tcp_default_mss ) 65535 )
        ( vec_push [u] out # u 3 ) ( vec_push [u] out # u 3 )
        ( vec_push [u] out # u & ? >= wscale 0 wscale 0 255 )
        ( vec_push [u] out # u 0 )  // end-of-options pad to a 4-byte boundary
    } {}
    : ~ i k 0
    ~ < k pay_len {
        ( vec_push [u] out ?? ( vec_get [u] payload + pay_off k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    : i total + doff pay_len
    : i s ( inet_sum_add ( ip4_pseudo_sum src_ip dst_ip ( ip_proto_tcp ) total ) out start total )
    : i ck ( inet_finish s )
    // Unlike UDP, a TCP checksum of zero is a real value — there is no
    // "no checksum" encoding to collide with, so no substitution here.
    : b _a ( vec_set [u] out + start 16 # u & >> ck 8 255 )
    : b _b ( vec_set [u] out + start 17 # u & ck 255 )
}
