// stdlib/net/nat.nu — NAT traversal primitives (RFC 5389/8489 ecosystem).
//
// **Phase 1 of TODO §7.4**, building on net/stun.nu. Three pieces a peer
// needs before it can reach another peer across NATs:
//
//   1. Candidate gathering — the addresses at which we *might* be reachable:
//      host candidates (our own interface IPs, IPv6 preferred — often a
//      direct path with no traversal) + server-reflexive candidates (the
//      public endpoint a STUN server observed for our socket).
//   2. NAT-type probe — query TWO STUN servers on the SAME socket and
//      compare the reflexive endpoints. Equal ⇒ endpoint-independent
//      mapping (cone — punchable). Different ⇒ address/port-dependent
//      (symmetric / CGNAT — punching won't work, short-circuit to a relay).
//   3. UDP hole punch — simultaneous-open: both peers fire tokened PING
//      datagrams at each other's reflexive endpoint until one round trip
//      completes, opening the NAT mappings in both directions.
//
// Host candidates are discovered WITHOUT getifaddrs: a throwaway UDP socket
// "connected" to a reference public address makes getsockname() report the
// local IP the kernel would route through — no packet is ever sent (UDP
// connect only fixes the route). This reuses std/udp.nu as the §7.4 plan
// directs and stays portable (wasm / RISC-V / mingw).
//
// The punch codec and the NAT-type classifier are pure and deterministic
// (offline-testable); the gather/probe/punch wrappers add the UDP I/O.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/net/stun.nu`

// ── candidate kinds ──────────────────────────────────────────────
@ cand_host → i { ^ 0 }

@ cand_srflx → i { ^ 1 }

@ cand_relay → i { ^ 2 }

: Candidate {
    String host
    i port
    i family  // 1 = IPv4, 2 = IPv6
    i kind  // 0 host, 1 server-reflexive, 2 relay
}

// ── NAT mapping types ────────────────────────────────────────────
@ nat_type_unknown → i { ^ 0 }

@ nat_type_independent → i { ^ 1 }  // cone — hole punch can work
@ nat_type_symmetric → i { ^ 2 }  // per-dest mapping — go straight to relay

@ nat_punchable i t → b { ^ == t 1 }

// ── address-string helpers (handle "1.2.3.4:port" and "[v6]:port") ──

// Normalize an IPv4-mapped IPv6 literal ("::ffff:1.2.3.4") down to its
// plain IPv4 form — a dual-stack socket reports local v4 addresses this
// way, but it is NOT a real IPv6 path. Consumes `h`, returns a fresh
// String (or `h` unchanged when it isn't a mapped address).
@ __unmap String h → String {
    : i n ( string_len h )
    ? < n 7 { ^ h } {}
    : s cs ( string_data h )
    : *u sp # *u cs
    : b mapped & == # i . sp 0 58 & == # i . sp 1 58 & == # i . sp 2 102 & == # i . sp 3 102 & == # i . sp 4 102 & == # i . sp 5 102 == # i . sp 6 58
    ? ! mapped { ^ h } {}
    : ~ b dot F : ~ i k 7
    ~ < k n { ? == # i . sp k 46 { = dot T } {} = k + k 1 }
    ? ! dot { ^ h } {}
    : String v4 ( string_with_cap - n 7 )
    : ~ i j 7
    ~ < j n { ( string_push_char v4 # i . sp j ) = j + j 1 }
    ( string_free h )
    ^ v4
}

// Host part, brackets stripped for IPv6, IPv4-mapped form normalized.
@ __addr_host String addr → String {
    : s cs ( string_data addr )
    : i n ( string_len addr )
    : *u sp # *u cs
    // bracketed IPv6: [host]:port
    ? & > n 0 == # i . sp 0 91 {  // '['
        : String h ( string_with_cap n )
        : ~ i e 1
        ~ & < e n != # i . sp e 93 {  // ']'
            ( string_push_char h # i . sp e ) = e + e 1
        }
        ^ ( __unmap h )
    } {}
    // IPv4 (or bare host): split on the last ':'
    : ~ i colon - 0 1
    : ~ i k 0
    ~ < k n { ? == # i . sp k 58 { = colon k } {} = k + k 1 }
    ? < colon 0 { ^ ( string_from ( string_data addr ) ) } {}
    : String h2 ( string_with_cap colon )
    : ~ i j 0
    ~ < j colon { ( string_push_char h2 # i . sp j ) = j + j 1 }
    ^ h2
}

// Port part (after the last ':'). 0 if absent.
@ __addr_port String addr → i {
    : s cs ( string_data addr )
    : i n ( string_len addr )
    : *u sp # *u cs
    : ~ i colon - 0 1
    : ~ i k 0
    ~ < k n { ? == # i . sp k 58 { = colon k } {} = k + k 1 }
    ? < colon 0 { ^ 0 } {}
    : ~ i port 0
    : ~ i d + colon 1
    ~ < d n {
        : i c # i . sp d
        ? & >= c 48 <= c 57 { = port + * port 10 - c 48 } {}
        = d + d 1
    }
    ^ port
}

// A numeric IP is IPv6 iff it contains a ':'.
@ __ip_family String ip → i {
    : s cs ( string_data ip )
    : i n ( string_len ip )
    : *u sp # *u cs
    : ~ b v6 F : ~ i k 0
    ~ < k n { ? == # i . sp k 58 { = v6 T } {} = k + k 1 }
    ^ ? v6 2 1
}

// ── host candidate (throwaway connected socket → routable local IP) ──

@ __local_ip_for s ref_host i ref_port → String {
    : !UdpSocket NetErr r ( udp_bind_any )
    : String out ?? r {
        T sk → {
            : !v NetErr cr ( udp_connect sk ref_host ref_port )
            : String ip ?? cr {
                T _ → {
                    : String la ( udp_local_addr sk )
                    : String h ( __addr_host la )
                    ( string_free la )
                    h
                }
                F _ → ( string_from `` )
            }
            ( udp_close sk )
            ip
        }
        F _ → ( string_from `` )
    }
    ^ out
}

// Our host candidate: the local IP the kernel routes toward `ref_host`,
// paired with the port our transport socket is bound to. None if the route
// can't be determined.
@ nat_host_candidate UdpSocket sock s ref_host i ref_port → ?Candidate {
    : String la ( udp_local_addr sock )
    : i app_port ( __addr_port la )
    ( string_free la )
    : String ip ( __local_ip_for ref_host ref_port )
    ? == ( string_len ip ) 0 {
        ( string_free ip )
        ^ @ ?Candidate { F # Candidate 0 }
    } {}
    : i fam ( __ip_family ip )
    ^ @ ?Candidate { T @ Candidate { ip app_port fam 0 } }
}

// Our server-reflexive candidate via one STUN Binding round trip.
@ nat_srflx_candidate UdpSocket sock s stun_host i stun_port i timeout_ms → ?Candidate {
    : ?StunAddr sa ( stun_query sock stun_host stun_port timeout_ms )
    : ?Candidate out ?? sa {
        T a → {
            : String h ( string_from ( string_data . a host ) )
            : i p . a port
            : i f . a family
            ( stun_addr_free a )
            @ ?Candidate { T @ Candidate { h p f 1 } }
        }
        F → @ ?Candidate { F # Candidate 0 }
    }
    ^ out
}

// ── candidate set (Vec of *Candidate) ────────────────────────────

@ __box_cand Candidate c → s {
    : *Candidate p # *Candidate ( nurl_alloc Z Candidate )
    = . p host . c host  // moves the owned String into the heap node
    = . p port . c port
    = . p family . c family
    = . p kind . c kind
    ^ # s p
}

@ __cand_eq * Candidate a Candidate b → b {
    ^ & == . a port . b port != 0 ( nurl_str_eq ( string_data . a host ) ( string_data . b host ) )
}

// Add a candidate unless an equal (host+port) one is already present; the
// duplicate's owned String is released.
@ __maybe_add ( Vec s ) cs Candidate c → v {
    : i n ( vec_len [s] cs )
    : ~ b dup F : ~ i k 0
    ~ & ! dup < k n {
        : s pp ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Candidate p # *Candidate pp
            ? ( __cand_eq p c ) { = dup T } {}
        } {}
        = k + k 1
    }
    ? dup { ( string_free . c host ) } { ( vec_push [s] cs # s ( __box_cand c ) ) }
}

// Gather host + server-reflexive candidates on `sock` using one STUN
// server (its address doubles as the route reference for the host
// candidate). Returns a Vec s of *Candidate; free with nat_candidates_free.
@ nat_gather UdpSocket sock s stun_host i stun_port i timeout_ms → ( Vec s ) {
    : ( Vec s ) cs ( vec_new [s] )
    : ?Candidate hc ( nat_host_candidate sock stun_host stun_port )
    ?? hc { T c → ( __maybe_add cs c ) F → {} }
    : ?Candidate sc ( nat_srflx_candidate sock stun_host stun_port timeout_ms )
    ?? sc { T c → ( __maybe_add cs c ) F → {} }
    ^ cs
}

@ nat_candidates_free ( Vec s ) cs → v {
    : i n ( vec_len [s] cs )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Candidate p # *Candidate pp
            ( string_free . p host )
            ( nurl_free # s p )
        } {}
        = k + k 1
    }
    ( vec_free [s] cs )
}

// ── NAT-type probe ───────────────────────────────────────────────

// Classify from two reflexive observations: same endpoint ⇒ independent
// (cone), differing ⇒ symmetric. Either missing ⇒ unknown. Pure.
@ nat_classify ? StunAddr a ? StunAddr b → i {
    : ~ i t 0
    ?? a {
        T sa → {
            ?? b {
                T sb → {
                    : b same & == . sa port . sb port != 0 ( nurl_str_eq ( string_data . sa host ) ( string_data . sb host ) )
                    = t ? same 1 2
                }
                F → {}
            }
        }
        F → {}
    }
    ^ t
}

// Probe NAT mapping type by querying two distinct STUN servers on the SAME
// socket and comparing the reflexive endpoints.
@ nat_probe UdpSocket sock s stun_a i port_a s stun_b i port_b i timeout_ms → i {
    : ?StunAddr a ( stun_query sock stun_a port_a timeout_ms )
    : ?StunAddr b ( stun_query sock stun_b port_b timeout_ms )
    : i t ( nat_classify a b )
    ?? a { T sa → ( stun_addr_free sa ) F → {} }
    ?? b { T sb → ( stun_addr_free sb ) F → {} }
    ^ t
}

// ── UDP hole punch (simultaneous open) ───────────────────────────
//
// Punch datagram: magic "NURP" (0x4E555250, 4 bytes BE) + kind (1 byte:
// 0 PING / 1 PONG) + an out-of-band-shared token. The token (exchanged via
// the rendezvous service in Phase 3) makes a punch packet unspoofable and
// lets the transport demux punch traffic from session data.

@ __punch_magic → i { ^ 1314080336 }  // "NURP"
@ punch_ping → i { ^ 0 }

@ punch_pong → i { ^ 1 }

: PunchMsg {
    i kind
    ( Vec u ) token
}

@ punch_msg_free PunchMsg m → v { ( vec_free [u] . m token ) }

@ nat_punch_build i kind ( Vec u ) token → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( bytes_push_u32_be m # u32 ( __punch_magic ) )
    ( vec_push [u] m # u kind )
    ( vec_extend [u] m token )
    ^ m
}

// Cheap magic check so the transport can demux punch packets from data.
@ nat_is_punch ( Vec u ) msg → b {
    ? < ( vec_len [u] msg ) 5 { ^ F } {}
    : i mg ?? ( bytes_read_u32_be msg 0 ) { T x → # i x F → -1 }
    ^ == mg ( __punch_magic )
}

@ nat_punch_parse ( Vec u ) msg → ?PunchMsg {
    ? ! ( nat_is_punch msg ) { ^ @ ?PunchMsg { F # PunchMsg 0 } } {}
    : i kind ?? ( vec_get [u] msg 4 ) { T x → # i x F → -1 }
    : i n ( vec_len [u] msg )
    : ( Vec u ) tok ( vec_new [u] )
    : ~ i k 5
    ~ < k n { ?? ( vec_get [u] msg k ) { T b → ( vec_push [u] tok b ) F → {} } = k + k 1 }
    ^ @ ?PunchMsg { T @ PunchMsg { kind tok } }
}

@ __tok_eq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

// Fire tokened PINGs at host:port until a matching punch comes back (on a
// PING we answer PONG so the peer completes too). T iff the path opened
// within `attempts` rounds of `interval_ms`. Run this on BOTH peers at once.
@ nat_hole_punch UdpSocket sock s host i port ( Vec u ) token i attempts i interval_ms → b {
    ( udp_set_timeout sock interval_ms )
    : ( Vec u ) ping ( nat_punch_build ( punch_ping ) token )
    : ( Vec u ) pong ( nat_punch_build ( punch_pong ) token )
    : ~ b ok F
    : ~ i k 0
    ~ & ! ok < k attempts {
        : !i NetErr sr ( udp_send_to sock ping host port )
        ?? sr { T _ → {} F _ → {} }
        : !UdpPacket NetErr rr ( udp_recv_from sock 256 )
        ?? rr {
            T pkt → {
                ?? ( nat_punch_parse . pkt data ) {
                    T pm → {
                        ? ( __tok_eq . pm token token ) {
                            ? == . pm kind ( punch_ping ) {
                                : !i NetErr ar ( udp_send_to sock pong host port )
                                ?? ar { T _ → {} F _ → {} }
                            } {}
                            = ok T
                        } {}
                        ( punch_msg_free pm )
                    }
                    F → {}
                }
                ( udp_packet_free pkt )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [u] ping )
    ( vec_free [u] pong )
    ^ ok
}
