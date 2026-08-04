// stdlib/net/arp.nu — ARP for IPv4-over-Ethernet (RFC 826), sans-IO.
//
// PURE — parse, build, and a cache whose expiry is driven by a clock
// the caller passes in. Nothing here reads a timer or a socket, so the
// whole resolve/expire life cycle is testable with a scripted clock.
//
// CACHE DESIGN
//
// Entries are scalar-only, so the table is a `( Vec ArpEntry )` and an
// update is read-modify-`vec_set` — no pointers, no per-entry
// allocation, no ownership dance on lookup (the hot path).
//
// An entry is INCOMPLETE while a request is outstanding, RESOLVED once
// a reply arrives. The distinction is what keeps a single unreachable
// destination from emitting one ARP request per outbound packet: the
// caller queues the packet, and the INCOMPLETE entry rate-limits
// retries to one per `arp_retry_ms`.
//
// SECURITY NOTE — deliberate, not an oversight: this cache updates
// only from replies to requests we sent, and from requests addressed
// to our own IP (the standard "he's asking for me, so learn him" case
// in RFC 826). It does NOT learn from arbitrary broadcast traffic.
// Gratuitous-ARP learning is the classic LAN spoofing vector, and a
// unikernel with one gateway gains nothing from it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`

// ── constants ────────────────────────────────────────────────────

@ arp_op_request → i { ^ 1 }

@ arp_op_reply → i { ^ 2 }

@ arp_pkt_len → i { ^ 28 }

// An entry with no traffic dies after this long; a resolved entry is
// refreshed by any reply, so a busy gateway never expires.
@ arp_ttl_ms → i { ^ 60000 }

// One outstanding request per destination per this interval.
@ arp_retry_ms → i { ^ 1000 }

// Give up on an unanswered address after this many retries.
@ arp_max_retries → i { ^ 3 }

@ arp_state_free → i { ^ 0 }

@ arp_state_incomplete → i { ^ 1 }

@ arp_state_resolved → i { ^ 2 }

// ── parse / build ────────────────────────────────────────────────

: ArpPkt {
    i op
    i sender_mac
    i sender_ip
    i target_mac
    i target_ip
    b valid
}

@ __arp_mac ( Vec u ) v i off → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 6 {
        : i b ?? ( vec_get [u] v + off k ) { T x → # i x F → 0 }
        = acc | << acc 8 b
        = k + k 1
    }
    ^ acc
}

// Parse an ARP packet at `off`, with `avail` bytes present. Only
// Ethernet/IPv4 ARP is accepted; every other hardware/protocol pair is
// rejected rather than mis-parsed.
@ arp_parse ( Vec u ) buf i off i avail → ArpPkt {
    ? < avail 28 { ^ @ ArpPkt { 0 0 0 0 0 F } } {}
    : i htype ?? ( bytes_read_u16_be buf off ) { T x → # i x F → 0 }
    : i ptype ?? ( bytes_read_u16_be buf + off 2 ) { T x → # i x F → 0 }
    : i hlen ?? ( vec_get [u] buf + off 4 ) { T x → # i x F → 0 }
    : i plen ?? ( vec_get [u] buf + off 5 ) { T x → # i x F → 0 }
    ? || != htype 1 || != ptype ( ethertype_ipv4 ) || != hlen 6 != plen 4 {
        ^ @ ArpPkt { 0 0 0 0 0 F }
    } {}
    : i op ?? ( bytes_read_u16_be buf + off 6 ) { T x → # i x F → 0 }
    ? && != op 1 != op 2 { ^ @ ArpPkt { 0 0 0 0 0 F } } {}
    ^ @ ArpPkt {
        op
        ( __arp_mac buf + off 8 )
        ?? ( bytes_read_u32_be buf + off 14 ) { T x → # i x F → 0 }
        ( __arp_mac buf + off 18 )
        ?? ( bytes_read_u32_be buf + off 24 ) { T x → # i x F → 0 }
        T
    }
}

// Append a complete Ethernet frame carrying one ARP packet.
@ arp_push_frame ( Vec u ) out i op i eth_dst i sender_mac i sender_ip i target_mac i target_ip → v {
    ( eth_push_header out eth_dst sender_mac ( ethertype_arp ) )
    ( bytes_push_u16_be out # u16 1 )  // hardware type: Ethernet
    ( bytes_push_u16_be out # u16 ( ethertype_ipv4 ) )
    ( vec_push [u] out # u 6 )
    ( vec_push [u] out # u 4 )
    ( bytes_push_u16_be out # u16 & op 65535 )
    ( eth_push_mac out sender_mac )
    ( bytes_push_u32_be out # u32 & sender_ip 4294967295 )
    ( eth_push_mac out target_mac )
    ( bytes_push_u32_be out # u32 & target_ip 4294967295 )
}

// "Who has target_ip? Tell sender." Broadcast, target MAC zero.
@ arp_push_request ( Vec u ) out i sender_mac i sender_ip i target_ip → v {
    ( arp_push_frame out ( arp_op_request ) ( mac_broadcast ) sender_mac sender_ip 0 target_ip )
}

@ arp_push_reply ( Vec u ) out i sender_mac i sender_ip i target_mac i target_ip → v {
    ( arp_push_frame out ( arp_op_reply ) target_mac sender_mac sender_ip target_mac target_ip )
}

// ── cache ────────────────────────────────────────────────────────

: ArpEntry {
    i ip
    i mac
    i state
    i expires_at  // RESOLVED: entry death. INCOMPLETE: next retry due.
    i retries
}

: ArpCache {
    ( Vec ArpEntry ) entries
    i max
}

@ arp_cache_new i max → *ArpCache {
    : *ArpCache c # *ArpCache ( nurl_alloc Z ArpCache )
    = . c entries ( vec_new [ArpEntry] )
    = . c max ? > max 0 max 64
    ^ c
}

@ arp_cache_free * ArpCache c → v {
    ( vec_free [ArpEntry] . c entries )
    ( free c )
}

@ __arp_find * ArpCache c i ip → i {
    : i n ( vec_len [ArpEntry] . c entries )
    : ~ i k 0
    ~ < k n {
        : ArpEntry e ?? ( vec_get [ArpEntry] . c entries k ) {
            T x → x
            F → @ ArpEntry { 0 0 0 0 0 }
        }
        ? && == . e ip ip != . e state ( arp_state_free ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Resolved MAC for `ip`, if the entry is present and unexpired.
@ arp_cache_lookup * ArpCache c i ip i now → ?i {
    : i idx ( __arp_find c ip )
    ? < idx 0 { ^ @ ?i { F 0 } } {}
    : ArpEntry e ?? ( vec_get [ArpEntry] . c entries idx ) {
        T x → x
        F → @ ArpEntry { 0 0 0 0 0 }
    }
    ? != . e state ( arp_state_resolved ) { ^ @ ?i { F 0 } } {}
    ? > now . e expires_at { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T . e mac }
}

// Evict the oldest slot when the table is full. A fixed-size table is
// the point: an unbounded cache is a remote memory-exhaustion vector,
// and a unikernel's whole heap is its budget.
@ __arp_slot * ArpCache c i now → i {
    : i n ( vec_len [ArpEntry] . c entries )
    : ~ i k 0
    ~ < k n {
        : ArpEntry e ?? ( vec_get [ArpEntry] . c entries k ) {
            T x → x
            F → @ ArpEntry { 0 0 0 0 0 }
        }
        ? || == . e state ( arp_state_free ) > now . e expires_at { ^ k } {}
        = k + k 1
    }
    ? < n . c max {
        ( vec_push [ArpEntry] . c entries @ ArpEntry { 0 0 0 0 0 } )
        ^ n
    } {}
    // Full and nothing expired — evict the entry closest to death.
    : ~ i best 0
    : ~ i best_exp -1
    : ~ i j 0
    ~ < j n {
        : ArpEntry e ?? ( vec_get [ArpEntry] . c entries j ) {
            T x → x
            F → @ ArpEntry { 0 0 0 0 0 }
        }
        ? || < best_exp 0 < . e expires_at best_exp {
            = best j
            = best_exp . e expires_at
        } {}
        = j + j 1
    }
    ^ best
}

// Record a resolved binding. Called for replies we asked for and for
// requests addressed to us — never for arbitrary observed traffic.
@ arp_cache_insert * ArpCache c i ip i mac i now → v {
    : ~ i idx ( __arp_find c ip )
    ? < idx 0 { = idx ( __arp_slot c now ) } {}
    : b _ok ( vec_set [ArpEntry] . c entries idx @ ArpEntry {
        ip
        mac
        ( arp_state_resolved )
        + now ( arp_ttl_ms )
        0
    } )
}

// Should we emit a request for `ip` right now?
//
// Returns T at most once per `arp_retry_ms` per destination, and stops
// after `arp_max_retries` — the rate limit lives in the cache rather
// than in the caller precisely so every send path inherits it.
@ arp_cache_should_request * ArpCache c i ip i now → b {
    : i idx ( __arp_find c ip )
    ? < idx 0 {
        : i slot ( __arp_slot c now )
        : b _ok ( vec_set [ArpEntry] . c entries slot @ ArpEntry {
            ip
            0
            ( arp_state_incomplete )
            + now ( arp_retry_ms )
            1
        } )
        ^ T
    } {}
    : ArpEntry e ?? ( vec_get [ArpEntry] . c entries idx ) {
        T x → x
        F → @ ArpEntry { 0 0 0 0 0 }
    }
    ? == . e state ( arp_state_resolved ) { ^ F } {}
    ? < now . e expires_at { ^ F } {}
    ? >= . e retries ( arp_max_retries ) { ^ F } {}
    : b _ok ( vec_set [ArpEntry] . c entries idx @ ArpEntry {
        ip
        0
        ( arp_state_incomplete )
        + now ( arp_retry_ms )
        + . e retries 1
    } )
    ^ T
}

// Has resolution of `ip` failed for good? The send path turns this
// into a "host unreachable" error instead of queueing forever.
@ arp_cache_failed * ArpCache c i ip i now → b {
    : i idx ( __arp_find c ip )
    ? < idx 0 { ^ F } {}
    : ArpEntry e ?? ( vec_get [ArpEntry] . c entries idx ) {
        T x → x
        F → @ ArpEntry { 0 0 0 0 0 }
    }
    ^ && && == . e state ( arp_state_incomplete ) >= . e retries ( arp_max_retries ) >= now . e expires_at
}

// Drop expired entries. Optional hygiene — lookup already treats an
// expired entry as absent — but it frees slots for new destinations.
@ arp_cache_expire * ArpCache c i now → i {
    : i n ( vec_len [ArpEntry] . c entries )
    : ~ i freed 0
    : ~ i k 0
    ~ < k n {
        : ArpEntry e ?? ( vec_get [ArpEntry] . c entries k ) {
            T x → x
            F → @ ArpEntry { 0 0 0 0 0 }
        }
        ? && != . e state ( arp_state_free ) > now . e expires_at {
            : b _ok ( vec_set [ArpEntry] . c entries k @ ArpEntry { 0 0 0 0 0 } )
            = freed + freed 1
        } {}
        = k + k 1
    }
    ^ freed
}
