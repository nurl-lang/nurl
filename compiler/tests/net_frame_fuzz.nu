// net_frame_fuzz.nu — structural fuzz of the frame path: bytes off the
// wire, straight into the sans-IO stack.
//
// `net_tcp_fuzz` fuzzes the TCP state machine with segments that are
// already parsed. This one starts one layer lower, where a unikernel
// actually lives: an arbitrary sequence of bytes arrives from a device,
// and `stack_rx` is the first thing in the machine that looks at it.
// Ethernet, ARP, IPv4 (with options), ICMP and UDP headers are all
// parsed there, from a buffer whose contents nobody chose.
//
// Deterministic (an LCG seeded by a constant), so a failure reproduces
// exactly. The generator mixes four populations, because pure noise
// mostly exercises the first `if` and nothing else:
//
//   * uniform random bytes of a random length, including 0 and 1;
//   * a well-formed frame addressed to us, with ONE byte flipped —
//     the population that actually reaches the deep parsers;
//   * a well-formed frame with a header field set to an extreme
//     (IHL 15, total_len 65535, a length that claims more than arrived);
//   * a truncated well-formed frame, cut at a random point.
//
// The oracle is not "it did not crash": NURL's accessors are bounds
// checked, so a parser that reads past the end gets `F` rather than a
// fault, and the bug shows up as a WRONG ANSWER instead. So what is
// asserted is what the layer above is entitled to believe:
//
//   1. Any payload the stack hands up lies inside the frame it was
//      given — `payload_off + payload_len <= frame length`. This is
//      what a missing "total_len fits in what arrived" check breaks,
//      and the caller who trusts it reads whatever is next in memory.
//   2. Every dropped frame carries exactly one reason, in range, and
//      the per-reason counters add up to the number of drops.
//   3. Every reply the stack emits is a frame a device could send:
//      at least 14 bytes, an ethertype we actually speak, and — for
//      IPv4 — a header checksum that verifies and a total_len that
//      fits inside the frame we built.
//   4. A frame not addressed to us never produces a reply. An
//      appliance that answers other machines' traffic is a reflector.
//   5. Nothing is emitted for a dropped frame, and `emitted` agrees
//      with what the packet buffer actually gained.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/icmp.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/stack.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ our_mac → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ peer_mac → i { ^ 2199023255554 }  // 02:00:00:00:00:02

@ our_ip → i { ^ ( ipv4_make 10 0 2 15 ) }

@ peer_ip → i { ^ ( ipv4_make 10 0 2 16 ) }

@ other_mac → i { ^ 2199023255807 }  // 02:00:00:00:00:ff — not us

@ mask24 → i { ^ 4294967040 }

@ lcg i st → i { ^ & + * st 6364136223846793005 1442695040888963407 4294967295 }

// A well-formed UDP frame from the peer to us, built the way the stack
// itself would build one. The mutators below start from this, because a
// generator that never produces a valid frame never gets past line one
// of the parser.
@ __good_frame ( Vec u ) out i payload_len → v {
    ( vec_clear [u] out )
    : ( Vec u ) pay ( vec_new [u] )
    : ~ i k 0
    ~ < k payload_len { ( vec_push [u] pay # u & + k 65 255 ) = k + k 1 }

    : ( Vec u ) dg ( vec_new [u] )
    ( udp4_push dg ( peer_ip ) ( our_ip ) 4000 4001 pay 0 payload_len )
    ( eth_push_header out ( our_mac ) ( peer_mac ) ( ethertype_ipv4 ) )
    ( ip4_push_header out ( peer_ip ) ( our_ip ) ( ip_proto_udp ) ( vec_len [u] dg ) 7 64 T )
    ( vec_extend [u] out dg )
    ( vec_free [u] dg )
    ( vec_free [u] pay )
}

// An ARP request for our address — the other frame that makes the stack
// answer, and therefore the other one worth mutating.
@ __good_arp ( Vec u ) out → v {
    ( vec_clear [u] out )
    ( eth_push_header out ( mac_broadcast ) ( peer_mac ) ( ethertype_arp ) )
    ( arp_push_request out ( peer_mac ) ( peer_ip ) ( our_ip ) )
}

// An ICMP echo request — the third frame the stack answers, and the one
// whose reply is built from the request's own bytes.
@ __good_ping ( Vec u ) out i payload_len → v {
    ( vec_clear [u] out )
    : ( Vec u ) pay ( vec_new [u] )
    : ~ i k 0
    ~ < k payload_len { ( vec_push [u] pay # u & + k 33 255 ) = k + k 1 }
    : ( Vec u ) msg ( vec_new [u] )
    ( icmp_push msg ( icmp_echo_request ) 0 1234 7 pay 0 payload_len )
    ( eth_push_header out ( our_mac ) ( peer_mac ) ( ethertype_ipv4 ) )
    ( ip4_push_header out ( peer_ip ) ( our_ip ) ( ip_proto_icmp ) ( vec_len [u] msg ) 9 64 T )
    ( vec_extend [u] out msg )
    ( vec_free [u] msg )
    ( vec_free [u] pay )
}

// One of the three frames this stack has an answer for, unmutated. A
// generator that only ever produces broken input never reaches the code
// that builds a reply — and "no reply was ever emitted" is a fuzz run
// that proved nothing about the reply path.
@ __good_any ( Vec u ) out i which i len → v {
    ? == % which 3 0 { ( __good_arp out ) } {
        ? == % which 3 1 { ( __good_ping out len ) } { ( __good_frame out len ) }
    }
}

// Point a well-formed frame at a third machine, by rewriting the six
// bytes of destination MAC and nothing else.
@ __readdress ( Vec u ) f → v {
    ? < ( vec_len [u] f ) 6 { ^ } {}
    : ~ i k 0
    ~ < k 6 {
        : b _s ( vec_set [u] f k # u & >> ( other_mac ) * 8 - 5 k 255 )
        = k + k 1
    }
}

@ __rand_bytes ( Vec u ) out i n i seed → i {
    : ~ i s seed
    ( vec_clear [u] out )
    : ~ i k 0
    ~ < k n {
        = s ( lcg s )
        ( vec_push [u] out # u & >> s 13 255 )
        = k + k 1
    }
    ^ s
}

// Is this frame addressed to us? Answered from the bytes, independently
// of the stack, so invariant 4 has a second opinion rather than the
// stack's own.
@ __addressed_to_us ( Vec u ) f → b {
    ? < ( vec_len [u] f ) 6 { ^ F } {}
    : ~ i dst 0
    : ~ i k 0
    : ~ b all_ff T
    ~ < k 6 {
        : i b ?? ( vec_get [u] f k ) { T x → # i x F → 0 }
        = dst | << dst 8 b
        ? != b 255 { = all_ff F } {}
        = k + k 1
    }
    ^ || all_ff == dst ( our_mac )
}

// Invariant 3, applied to one emitted frame.
@ __reply_well_formed ( Vec u ) f → b {
    : i n ( vec_len [u] f )
    ? < n 14 { ^ F } {}
    : EthHdr eh ( eth_parse f )
    ? ! . eh valid { ^ F } {}
    ? == . eh ethertype ( ethertype_arp ) { ^ >= n 42 } {}
    ? != . eh ethertype ( ethertype_ipv4 ) { ^ F } {}
    : Ip4Hdr ih ( ip4_parse f . eh payload_off . eh payload_len )
    ? ! . ih valid { ^ F } {}
    ^ <= + . ih payload_off . ih payload_len n
}

@ main → i {
    : *NetStack st ( stack_new ( our_mac ) ( our_ip ) ( mask24 ) ( ipv4_make 10 0 2 1 ) )
    : *PktBuf out ( pktbuf_new )
    : ( Vec u ) frame ( vec_new [u] )

    : ~ i seed 20260806
    : ~ b payload_inside T
    : ~ b reason_sane T
    : ~ b replies_valid T
    : ~ b no_reflection T
    : ~ b emitted_agrees T
    : ~ i drops 0
    : ~ i handled 0
    : ~ i replies 0

    : ~ i round 0
    ~ < round 3000 {
        = seed ( lcg seed )
        : i shape % >> seed 7 5
        : i n % >> seed 17 200

        ? == shape 0 {
            = seed ( __rand_bytes frame n seed )
        } {
            ? == shape 1 {
                // a good frame with one byte flipped
                ? == % >> seed 23 3 0 { ( __good_arp frame ) } { ( __good_frame frame % >> seed 11 64 ) }
                : i len ( vec_len [u] frame )
                ? > len 0 {
                    : i at % >> seed 19 len
                    : i old ?? ( vec_get [u] frame at ) { T x → # i x F → 0 }
                    : b _s ( vec_set [u] frame at # u & ^^ old & >> seed 29 255 255 )
                } {}
            } {
                ? == shape 2 {
                    // a good frame with an extreme header field
                    ( __good_frame frame % >> seed 11 32 )
                    : i which % >> seed 27 4
                    ? == which 0 {
                        : b _a ( vec_set [u] frame 14 # u 79 )  // version 4, IHL 15
                    } {}
                    ? == which 1 {
                        : b _b ( vec_set [u] frame 16 # u 255 )  // total_len = 65535
                        : b _c ( vec_set [u] frame 17 # u 255 )
                    } {}
                    ? == which 2 {
                        : b _d ( vec_set [u] frame 20 # u 32 )  // MF set, offset 0
                        : b _e ( vec_set [u] frame 21 # u 1 )
                    } {}
                    // A UDP datagram with NO checksum (legal, RFC 768)
                    // whose length field claims far more than arrived.
                    // Zero checksum is the one path where the length is
                    // not cross-checked by anything else, so it is the
                    // one place a missing bounds test survives — and it
                    // is reachable by anyone who can send a packet.
                    ? == which 3 {
                        : b _f ( vec_set [u] frame 40 # u 0 )  // checksum
                        : b _g ( vec_set [u] frame 41 # u 0 )
                        : b _h ( vec_set [u] frame 38 # u 255 )  // length
                        : b _i ( vec_set [u] frame 39 # u 255 )
                    } {}
                } {
                    ? == shape 3 {
                        // a good frame, cut short
                        ( __good_frame frame % >> seed 11 48 )
                        : i len ( vec_len [u] frame )
                        : i keep % >> seed 21 + len 1
                        ~ > ( vec_len [u] frame ) keep { : ?u _p ( vec_pop [u] frame ) }
                    } {
                        // a frame the stack is supposed to answer — and,
                        // one time in three, the same frame addressed to
                        // somebody else. A stack that answers those is a
                        // reflector, and it is a population that random
                        // bytes never produce: a valid ARP request or
                        // echo request with a foreign destination has to
                        // be built on purpose.
                        ( __good_any frame % >> seed 25 3 % >> seed 11 40 )
                        ? == % >> seed 31 3 0 { ( __readdress frame ) } {}
                    }
                }
            }
        }

        : i flen ( vec_len [u] frame )
        : i before_total ( pktbuf_total out )
        : i before_count ( pktbuf_count out )
        : b for_us ( __addressed_to_us frame )

        : RxResult r ( stack_rx st frame * round 10 out )
        = handled + handled 1

        : i gained - ( pktbuf_total out ) before_total
        : i new_frames - ( pktbuf_count out ) before_count

        // 1. anything handed up must lie inside the frame
        ? || == . r kind ( rx_udp ) == . r kind ( rx_tcp ) {
            ? > + . r payload_off . r payload_len flen { = payload_inside F } {}
        } {}

        // 2. one reason, in range, and the counters agree
        ? == . r kind ( rx_dropped ) {
            = drops + drops 1
            ? || < . r reason 0 >= . r reason ( n_drop_reasons ) { = reason_sane F } {}
            ? != gained 0 { = emitted_agrees F } {}
        } {}

        // 5. `emitted` is what the buffer actually gained
        ? != . r emitted gained { = emitted_agrees F } {}

        // 3 + 4. every emitted frame is well formed, and only frames
        // addressed to us produce any
        ? > new_frames 0 {
            = replies + replies new_frames
            ? ! for_us { = no_reflection F } {}
            : ~ i idx before_count
            ~ < idx ( pktbuf_count out ) {
                : ( Vec u ) one ( vec_new [u] )
                : i _c ( pktbuf_copy_to one out idx )
                ? ! ( __reply_well_formed one ) { = replies_valid F } {}
                ( vec_free [u] one )
                = idx + idx 1
            }
        } {}

        ( pktbuf_clear out )
        = round + round 1
    }

    // The counters the stack keeps must add up to the drops observed:
    // a frame that vanished without landing in a bucket is exactly the
    // "some packets go missing" the drop accounting exists to prevent.
    : ~ i counted 0
    : ~ i ri 0
    ~ < ri ( n_drop_reasons ) {
        = counted + counted ( stack_drop_count st ri )
        = ri + ri 1
    }

    ( pb `every payload handed up lies inside its frame: ` payload_inside )
    ( pb `every drop has exactly one reason, in range: ` reason_sane )
    ( pb `drop counters add up: ` == counted drops )
    ( pb `every emitted frame is one a device could send: ` replies_valid )
    ( pb `frames not addressed to us are never answered: ` no_reflection )
    ( pb `emitted bytes agree with the buffer: ` emitted_agrees )
    ( pb `the fuzz completed without hanging: ` == handled 3000 )
    ( pb `the deep parsers were reached (some replies emitted): ` > replies 0 )

    ( vec_free [u] frame )
    ( pktbuf_free out )
    ( stack_free st )
    ^ 0
}
