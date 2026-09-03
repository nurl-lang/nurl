// stdlib/std/udp.nu — UDP datagram sockets (dual-stack IPv4/IPv6).
//
// Wraps runtime §18b. Wildcard binds are AF_INET6 + IPV6_V6ONLY=0 so
// one socket handles both IPv4 and IPv6 peers; binding to an explicit
// literal honours that literal's family.
//
// API surface:
//
//   ( udp_bind             s host i port )                    → ! UdpSocket NetErr
//   ( udp_bind_any                       )                    → ! UdpSocket NetErr (wildcard, ephemeral port)
//   ( udp_connect          UdpSocket s s host i port )        → ! v NetErr
//   ( udp_send_to          UdpSocket s ( Vec u ) bytes s host i port ) → ! i NetErr
//   ( udp_send_str_to      UdpSocket s s text s host i port ) → ! i NetErr
//   ( udp_recv_from        UdpSocket s i max )                → ! UdpPacket NetErr
//   ( udp_send             UdpSocket s ( Vec u ) bytes )      → ! i NetErr
//   ( udp_recv             UdpSocket s i max )                → ! ( Vec u ) NetErr
//   ( udp_close            UdpSocket s )                      → v
//   ( udp_peer_addr        UdpSocket s )                      → s (BORROWED)
//   ( udp_local_addr       UdpSocket s )                      → String (OWNED)
//   ( udp_set_timeout      UdpSocket s i ms )                 → v
//   ( udp_set_nonblock     UdpSocket s i on )                 → v
//   ( udp_set_broadcast    UdpSocket s i on )                 → ! v NetErr
//   ( udp_join_group       UdpSocket s s group s iface )      → ! v NetErr
//   ( udp_leave_group      UdpSocket s s group s iface )      → ! v NetErr
//   ( udp_set_multicast_ttl  UdpSocket s i ttl )              → ! v NetErr
//   ( udp_set_multicast_loop UdpSocket s i on  )              → ! v NetErr
//   ( udp_family           UdpSocket s )                      → i (AF_INET/AF_INET6)
//
// Address-carrying variants (no allocation, no resolver per datagram —
// the shape a packet-per-datagram transport such as QUIC needs):
//
//   ( udp_addr_new                                    )       → ( Vec u )  24 zero bytes
//   ( udp_addr_resolve     s host i port )                    → ! ( Vec u ) NetErr (once per peer)
//   ( udp_addr_format      ( Vec u ) addr )                   → String (OWNED) "ip:port" / "[ip]:port"
//   ( udp_addr_family      ( Vec u ) addr )                   → i  4 / 6 / 0
//   ( udp_addr_port        ( Vec u ) addr )                   → i
//   ( udp_addr_eq          ( Vec u ) a ( Vec u ) b )          → b
//   ( udp_recv_into        UdpSocket s ( Vec u ) buf ( Vec u ) from )            → ! i NetErr
//   ( udp_recv_into_deadline UdpSocket s ( Vec u ) buf ( Vec u ) from i ms )     → ! i NetErr (NetTimeout)
//   ( udp_send_addr        UdpSocket s ( Vec u ) bytes ( Vec u ) to )             → ! i NetErr
//   ( udp_setsockopt_int   UdpSocket s i level i opt i val )                     → ! v NetErr
//
//   `udp_recv_into` fills `buf` up to its CAPACITY (vec_with_cap sizes
//   the receive; the datagram length becomes the Vec's len) and writes
//   the sender into `from`, a 24-byte address from `udp_addr_new`.
//   Both Vecs stay owned by the caller and are reused across calls.
//
//   Address encoding (NURL's own, identical on every target):
//     [0] family 4/6 (0 = empty) · [1] 0 · [2..4) port BE ·
//     [4..20) address (IPv4 in the first 4 bytes) · [20..24) IPv6 scope
//   An IPv4 peer of a dual-stack socket is reported as family 4, never
//   as ::ffff:a.b.c.d, so `udp_addr_eq` compares peers regardless of the
//   socket that received them.
//
// Memory model:
//
//   * `UdpSocket` is a single-field opaque handle (`s raw`) wrapping a
//     heap `NurlUdp*` cast to i64. `udp_close` MUST be called exactly
//     once per Ok-path; Err arms NEVER carry a handle (the runtime
//     frees its half before returning).
//   * `udp_recv_from` returns an OWNED `UdpPacket { data peer }`.
//     Caller frees with `udp_packet_free`.
//   * `udp_send_to` / `udp_send` / `udp_send_str_to` BORROW their input
//     buffer — caller still owns the Vec[u] / `s` after the call.
//   * `udp_peer_addr` returns a BORROWED view into the handle (the
//     address of the last `recv_from` / `connect` peer). Copy via
//     `string_from` if a long-lived String is needed.
//   * `udp_local_addr` returns an OWNED String (caller frees via
//     `string_free`) — computed fresh from `getsockname` each call.
//
// Multicast `iface` argument:
//
//   * empty string ("")              default interface (INADDR_ANY / 0)
//   * IPv4 group → interface IP literal (e.g. "192.168.1.5")
//   * IPv6 group → numeric interface index (e.g. "2")
//
//   Interface-name → ifindex resolution is NOT bundled to keep Win32
//   builds free of the `-liphlpapi` link dep; NURL callers that need
//   it can layer a tiny `nurl_if_nametoindex` FFI on top.
//
// Error codes reuse the NetErr enum from `stdlib/std/net.nu` (NetBind,
// NetRead, NetWrite, NetClosed, NetTimeout, NetOther, …). NetClosed
// here means the FD has been freed (use-after-close), NOT a TCP-style
// peer EOF — UDP has no connection.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/async_ffi.nu`

// ── Runtime FFI bridge (§18b) ──────────────────────────────────────

& `c` @ nurl_udp_bind s host i port → i

& `c` @ nurl_udp_connect i handle s host i port → i

& `c` @ nurl_udp_send_to i handle s buf i n s host i port → i

& `c` @ nurl_udp_recv_from i handle s buf i n → i

& `c` @ nurl_udp_send i handle s buf i n → i

& `c` @ nurl_udp_recv i handle s buf i n → i

& `c` @ nurl_udp_peer_addr i handle → s

& `c` @ nurl_udp_local_addr i handle → s

& `c` @ nurl_udp_err_kind i handle → i

& `c` @ nurl_udp_get_fd i handle → i

& `c` @ nurl_udp_family i handle → i

& `c` @ nurl_udp_set_nonblock i handle i on → v

& `c` @ nurl_udp_set_timeout i handle i ms → v

& `c` @ nurl_udp_close i handle → v

& `c` @ nurl_udp_set_broadcast i handle i on → i

& `c` @ nurl_udp_join_group i handle s group s iface → i

& `c` @ nurl_udp_leave_group i handle s group s iface → i

& `c` @ nurl_udp_set_multicast_ttl i handle i ttl → i

& `c` @ nurl_udp_set_multicast_loop i handle i on → i

& `c` @ nurl_udp_recv_into i handle s buf i cap s addr_out → i

& `c` @ nurl_udp_send_addr i handle s buf i n s addr → i

& `c` @ nurl_udp_addr_resolve s host i port s addr_out → i

& `c` @ nurl_udp_addr_format s addr → s

& `c` @ nurl_udp_setsockopt_int i handle i level i opt i val → i

// ── Public types ───────────────────────────────────────────────────

: UdpSocket { s raw }

: UdpPacket {
    ( Vec u ) data
    String peer
}

// ── Lifecycle ──────────────────────────────────────────────────────

// Bind on host:port. Empty host → dual-stack wildcard. port=0 → kernel
// picks an ephemeral port (read it back with `udp_local_addr`).
@ udp_bind s host i port → !UdpSocket NetErr {
    : i raw ( nurl_udp_bind host port )
    ? == raw 0 { ^ @ !UdpSocket NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_udp_err_kind raw )
    ? != ek 0 {
        ( nurl_udp_close raw )
        ^ @ !UdpSocket NetErr { F ( _net_err_of ek ) }
    } {}
    : s rp # s raw
    : UdpSocket sk @ UdpSocket { rp }
    ^ @ !UdpSocket NetErr { T sk }
}

// Convenience — wildcard bind with the kernel choosing the port.
@ udp_bind_any → !UdpSocket NetErr {
    ^ ( udp_bind `` 0 )
}

// Switch the socket into "connected UDP" mode — only this peer's
// datagrams will be delivered, and `udp_send`/`udp_recv` may be used
// instead of the explicit sendto/recvfrom variants. Also wires up the
// kernel to report ICMP unreachables synchronously on the next call.
@ udp_connect UdpSocket sk s host i port → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_connect raw host port )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

@ udp_close UdpSocket sk → v {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_close raw )
}

// ── Address accessors ──────────────────────────────────────────────

// BORROWED view of the last-peer address ("ip:port" for IPv4,
// "[ip]:port" for IPv6). Empty until the first recv_from / connect.
@ udp_peer_addr UdpSocket sk → s {
    : s rp . sk raw
    : i raw # i rp
    ^ ( nurl_udp_peer_addr raw )
}

// OWNED String of the locally-bound endpoint (computed fresh from
// getsockname). After binding with port=0 this is how the caller
// discovers which port the kernel actually picked. Caller frees
// with `string_free`.
@ udp_local_addr UdpSocket sk → String {
    : s rp . sk raw
    : i raw # i rp
    : s raw_s ( nurl_udp_local_addr raw )
    : String out ( string_from raw_s )
    ( nurl_free raw_s )
    ^ out
}

@ udp_family UdpSocket sk → i {
    : s rp . sk raw
    : i raw # i rp
    ^ ( nurl_udp_family raw )
}

@ udp_get_fd UdpSocket sk → i {
    : s rp . sk raw
    : i raw # i rp
    ^ ( nurl_udp_get_fd raw )
}

// ── Socket options ─────────────────────────────────────────────────

@ udp_set_timeout UdpSocket sk i ms → v {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_timeout raw ms )
}

@ udp_set_nonblock UdpSocket sk i on → v {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_nonblock raw on )
}

@ udp_set_broadcast UdpSocket sk i on → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_set_broadcast raw on )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// ── Multicast ──────────────────────────────────────────────────────

@ udp_join_group UdpSocket sk s group s iface → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_join_group raw group iface )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

@ udp_leave_group UdpSocket sk s group s iface → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_leave_group raw group iface )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

@ udp_set_multicast_ttl UdpSocket sk i ttl → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_set_multicast_ttl raw ttl )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

@ udp_set_multicast_loop UdpSocket sk i on → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_set_multicast_loop raw on )
    ? != rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// ── UdpPacket helpers ──────────────────────────────────────────────

@ udp_packet_free UdpPacket p → v {
    : ( Vec u ) d . p data
    : String pr . p peer
    ( vec_free [u] d )
    ( string_free pr )
}

// ── Send / Receive ─────────────────────────────────────────────────

// Send a Vec[u] datagram to a specific host:port. UDP is message-
// oriented; if the request exceeds the link MTU it'll be IP-fragmented
// (or dropped on a DF-set v6 path). Returns the bytes actually sent.
@ udp_send_to UdpSocket sk ( Vec u ) bytes s host i port → !i NetErr {
    // Context-aware dispatch — see tcp_read_chunk's note.
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( udp_send_to_async sk bytes host port ) } {}
    : s rp . sk raw
    : i raw # i rp
    : i n ( vec_len [u] bytes )
    ? <= n 0 {
        // Allow zero-length datagrams — pass NULL buffer through.
        : i sent ( nurl_udp_send_to raw `` 0 host port )
        ? < sent 0 {
            : i ek ( nurl_udp_err_kind raw )
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        } {}
        ^ @ !i NetErr { T sent }
    } {}
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    : i sent ( nurl_udp_send_to raw pbuf n host port )
    ? < sent 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !i NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !i NetErr { T sent }
}

// String convenience — sends bytes [0..nurl_str_len) of `text`.
@ udp_send_str_to UdpSocket sk s text s host i port → !i NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i n ( nurl_str_len text )
    : i sent ( nurl_udp_send_to raw text n host port )
    ? < sent 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !i NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !i NetErr { T sent }
}

// Receive one datagram (up to `max` bytes). Returns OWNED UdpPacket
// with the source address. Truncation: if the actual datagram is
// larger than `max`, the kernel silently discards the excess; sizing
// `max` to 65 535 covers any IPv4/IPv6 payload.
@ udp_recv_from UdpSocket sk i max → !UdpPacket NetErr {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( udp_recv_from_async sk max ) } {}
    : s rp . sk raw
    : i raw # i rp
    ? <= max 0 {
        : ( Vec u ) v0 ( vec_new [u] )
        : String p0 ( string_new )
        ^ @ !UdpPacket NetErr { T @ UdpPacket { v0 p0 } }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    : i n ( nurl_udp_recv_from raw pbuf max )
    ? < n 0 {
        ( vec_free [u] v )
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !UdpPacket NetErr { F ( _net_err_of ek ) }
    } {}
    ( vec_set_len [u] v n )
    : s peer_raw ( nurl_udp_peer_addr raw )
    : String peer ( string_from peer_raw )
    ^ @ !UdpPacket NetErr { T @ UdpPacket { v peer } }
}

// Connected-mode send (after `udp_connect`).
@ udp_send UdpSocket sk ( Vec u ) bytes → !i NetErr {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( udp_send_async sk bytes ) } {}
    : s rp . sk raw
    : i raw # i rp
    : i n ( vec_len [u] bytes )
    ? <= n 0 {
        : i sent ( nurl_udp_send raw `` 0 )
        ? < sent 0 {
            : i ek ( nurl_udp_err_kind raw )
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        } {}
        ^ @ !i NetErr { T sent }
    } {}
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    : i sent ( nurl_udp_send raw pbuf n )
    ? < sent 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !i NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !i NetErr { T sent }
}

// Connected-mode receive — only datagrams from the connected peer are
// delivered. Returns the OWNED payload; use `udp_peer_addr` to recover
// the source address.
@ udp_recv UdpSocket sk i max → !( Vec u ) NetErr {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( udp_recv_async sk max ) } {}
    : s rp . sk raw
    : i raw # i rp
    ? <= max 0 {
        : ( Vec u ) v0 ( vec_new [u] )
        ^ @ !( Vec u ) NetErr { T v0 }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    : i n ( nurl_udp_recv raw pbuf max )
    ? < n 0 {
        ( vec_free [u] v )
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
    } {}
    ( vec_set_len [u] v n )
    ^ @ !( Vec u ) NetErr { T v }
}

// ── Fiber-aware async variants ────────────────────────────────────
//
// Mirror the sync entry points one-to-one. Inside a fiber, an
// EAGAIN/EWOULDBLOCK from the kernel is converted into a reactor
// park; the worker pthread stays free. From outside any fiber the
// reactor returns -1 and we fall back to the blocking variant
// transparently (see context-aware dispatch above).
//
// First call on a socket flips it to O_NONBLOCK; subsequent sync
// calls on the SAME handle will start surfacing NetTimeout on
// no-data — mixing sync + async on one socket is not supported.

@ udp_recv_from_async UdpSocket sk i max → !UdpPacket NetErr {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    ? <= max 0 {
        : ( Vec u ) v0 ( vec_new [u] )
        : String p0 ( string_new )
        ^ @ !UdpPacket NetErr { T @ UdpPacket { v0 p0 } }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    ~ T {
        : i n ( nurl_udp_recv_from raw pbuf max )
        ? >= n 0 {
            ( vec_set_len [u] v n )
            : s peer_raw ( nurl_udp_peer_addr raw )
            : String peer ( string_from peer_raw )
            ^ @ !UdpPacket NetErr { T @ UdpPacket { v peer } }
        } {}
        : i ek ( nurl_udp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_read fd - 0 1 )
            ? < rc 0 {
                ( vec_free [u] v )
                ^ @ !UdpPacket NetErr { F # NetErr NetTimeout }
            } {}
        } {
            ( vec_free [u] v )
            ^ @ !UdpPacket NetErr { F ( _net_err_of ek ) }
        }
    }
    ( vec_free [u] v )
    ^ @ !UdpPacket NetErr { F # NetErr NetOther }
}

@ udp_recv_async UdpSocket sk i max → !( Vec u ) NetErr {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    ? <= max 0 {
        : ( Vec u ) v0 ( vec_new [u] )
        ^ @ !( Vec u ) NetErr { T v0 }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    ~ T {
        : i n ( nurl_udp_recv raw pbuf max )
        ? >= n 0 {
            ( vec_set_len [u] v n )
            ^ @ !( Vec u ) NetErr { T v }
        } {}
        : i ek ( nurl_udp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_read fd - 0 1 )
            ? < rc 0 {
                ( vec_free [u] v )
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
        } {
            ( vec_free [u] v )
            ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
        }
    }
    ( vec_free [u] v )
    ^ @ !( Vec u ) NetErr { F # NetErr NetOther }
}

@ udp_send_to_async UdpSocket sk ( Vec u ) bytes s host i port → !i NetErr {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    : i n ( vec_len [u] bytes )
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    ~ T {
        : i sent ? <= n 0
        ( nurl_udp_send_to raw `` 0 host port )
        ( nurl_udp_send_to raw pbuf n host port )
        ? >= sent 0 { ^ @ !i NetErr { T sent } } {}
        : i ek ( nurl_udp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_write fd - 0 1 )
            ? < rc 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
        } {
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        }
    }
    ^ @ !i NetErr { F # NetErr NetOther }
}

@ udp_send_async UdpSocket sk ( Vec u ) bytes → !i NetErr {
    : s rp . sk raw
    : i raw # i rp
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    : i n ( vec_len [u] bytes )
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    ~ T {
        : i sent ? <= n 0
        ( nurl_udp_send raw `` 0 )
        ( nurl_udp_send raw pbuf n )
        ? >= sent 0 { ^ @ !i NetErr { T sent } } {}
        : i ek ( nurl_udp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_write fd - 0 1 )
            ? < rc 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
        } {
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        }
    }
    ^ @ !i NetErr { F # NetErr NetOther }
}

// ── Address-carrying variants ─────────────────────────────────────
//
// The entry points above were shaped for request/response tools: one
// fresh Vec + one peer String per received datagram, one name
// resolution per sent one. A transport that handles a datagram per
// packet (QUIC) cannot pay any of those per packet, so these variants
// move the buffer and the address to the caller and keep both across
// calls. They are fiber-aware like the rest of the file: inside a
// fiber EAGAIN parks on the reactor (with a deadline, for the
// `_deadline` form), outside one the socket blocks.

// A fresh, empty 24-byte address.
@ udp_addr_new → ( Vec u ) {
    : ( Vec u ) a ( vec_with_cap [u] 24 )
    : b _ok ( vec_resize_zeroed [u] a 24 )
    ^ a
}

@ __udp_addr_ptr ( Vec u ) a → s {
    // Callers hand in whatever they like; a short Vec is grown to the
    // 24 bytes the runtime writes/reads so no call ever runs past it.
    ? < ( vec_len [u] a ) 24 { : b _ok ( vec_resize_zeroed [u] a 24 ) } {}
    : *u p ( vec_data [u] a )
    ^ # s p
}

// host:port → address. A numeric literal never touches a resolver; a
// name costs one lookup — call this once per peer, not per packet.
@ udp_addr_resolve s host i port → !( Vec u ) NetErr {
    : ( Vec u ) a ( udp_addr_new )
    : i rc ( nurl_udp_addr_resolve host port ( __udp_addr_ptr a ) )
    ? < rc 0 {
        ( vec_free [u] a )
        ^ @ !( Vec u ) NetErr { F # NetErr NetOther }
    } {}
    ^ @ !( Vec u ) NetErr { T a }
}

// OWNED "ip:port" (IPv4) / "[ip]:port" (IPv6); "" for an empty address.
@ udp_addr_format ( Vec u ) a → String {
    : s raw_s ( nurl_udp_addr_format ( __udp_addr_ptr a ) )
    : String out ( string_from raw_s )
    ( nurl_free raw_s )
    ^ out
}

@ udp_addr_family ( Vec u ) a → i {
    ? < ( vec_len [u] a ) 24 { ^ 0 } {}
    ^ # i ?? ( vec_get [u] a 0 ) { T x → x F → 0 }
}

@ udp_addr_port ( Vec u ) a → i {
    ? < ( vec_len [u] a ) 24 { ^ 0 } {}
    : i hi # i ?? ( vec_get [u] a 2 ) { T x → x F → 0 }
    : i lo # i ?? ( vec_get [u] a 3 ) { T x → x F → 0 }
    ^ | << hi 8 lo
}

@ udp_addr_eq ( Vec u ) a ( Vec u ) b → b {
    ^ ( bytes_eq a b )
}

@ __udp_recv_into_raw i raw ( Vec u ) buf ( Vec u ) from → i {
    : i cap ( vec_cap [u] buf )
    : *u p ( vec_data [u] buf )
    : s pbuf # s p
    : i n ( nurl_udp_recv_into raw pbuf cap ( __udp_addr_ptr from ) )
    ? >= n 0 { : b _ok ( vec_set_len [u] buf n ) } {}
    ^ n
}

// Receive one datagram into `buf` (its capacity is the maximum; its
// length becomes the datagram size) and the sender into `from`.
// `deadline_ms` < 0 waits forever; otherwise Err(NetTimeout) when
// nothing arrived in time. Outside a fiber the deadline is applied as
// the socket's receive timeout (SO_RCVTIMEO) for the duration of the
// call, so the same contract holds on a plain OS thread.
@ udp_recv_into_deadline UdpSocket sk ( Vec u ) buf ( Vec u ) from i deadline_ms → !i NetErr {
    : s rp . sk raw
    : i raw # i rp
    ? <= ( vec_cap [u] buf ) 0 { ^ @ !i NetErr { F # NetErr NetRead } } {}
    : i fcur ( nurl_fiber_current )
    ? == fcur 0 {
        ? >= deadline_ms 0 { ( nurl_udp_set_timeout raw ? == deadline_ms 0 1 deadline_ms ) } {}
        : i n ( __udp_recv_into_raw raw buf from )
        ? >= deadline_ms 0 { ( nurl_udp_set_timeout raw 0 ) } {}
        ? < n 0 {
            : i ek ( nurl_udp_err_kind raw )
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        } {}
        ^ @ !i NetErr { T n }
    } {}
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    : i t0 ( nurl_monotonic_ns )
    ~ T {
        : i n ( __udp_recv_into_raw raw buf from )
        ? >= n 0 { ^ @ !i NetErr { T n } } {}
        : i ek ( nurl_udp_err_kind raw )
        ? != ek 7 { ^ @ !i NetErr { F ( _net_err_of ek ) } } {}
        : ~ i wait deadline_ms
        ? >= deadline_ms 0 {
            : i spent / - ( nurl_monotonic_ns ) t0 1000000
            = wait - deadline_ms spent
            ? <= wait 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
        } {}
        : i rc ( nurl_reactor_wait_read fd wait )
        ? == rc 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
        ? < rc 0 { ^ @ !i NetErr { F # NetErr NetOther } } {}
    }
    ^ @ !i NetErr { F # NetErr NetOther }
}

@ udp_recv_into UdpSocket sk ( Vec u ) buf ( Vec u ) from → !i NetErr {
    ^ ( udp_recv_into_deadline sk buf from - 0 1 )
}

// Send `bytes` to an address obtained from `udp_recv_into` or
// `udp_addr_resolve`. No resolver involved.
@ udp_send_addr UdpSocket sk ( Vec u ) bytes ( Vec u ) to → !i NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i n ( vec_len [u] bytes )
    : *u p ( vec_data [u] bytes )
    : s pbuf ? <= n 0 `` # s p
    : s pa ( __udp_addr_ptr to )
    : i fcur ( nurl_fiber_current )
    ? == fcur 0 {
        : i sent ( nurl_udp_send_addr raw pbuf n pa )
        ? < sent 0 {
            : i ek ( nurl_udp_err_kind raw )
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        } {}
        ^ @ !i NetErr { T sent }
    } {}
    ( nurl_udp_set_nonblock raw 1 )
    : i fd ( nurl_udp_get_fd raw )
    ~ T {
        : i sent ( nurl_udp_send_addr raw pbuf n pa )
        ? >= sent 0 { ^ @ !i NetErr { T sent } } {}
        : i ek ( nurl_udp_err_kind raw )
        ? != ek 7 { ^ @ !i NetErr { F ( _net_err_of ek ) } } {}
        : i rc ( nurl_reactor_wait_write fd - 0 1 )
        ? < rc 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
    }
    ^ @ !i NetErr { F # NetErr NetOther }
}

// setsockopt with an int value. `level` and `opt` come from
// `posix_const` (SOL_SOCKET, SO_REUSEPORT, IPPROTO_UDP, UDP_SEGMENT,
// IP_TOS, …); a name the platform lacks resolves to -1 and is refused
// here rather than handed to the kernel as a number.
@ udp_setsockopt_int UdpSocket sk i level i opt i val → !v NetErr {
    : s rp . sk raw
    : i raw # i rp
    : i rc ( nurl_udp_setsockopt_int raw level opt val )
    ? < rc 0 {
        : i ek ( nurl_udp_err_kind raw )
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T }
}
