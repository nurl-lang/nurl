// stdlib/net/inet.nu — shared primitives for the sans-IO network stack.
//
// The bottom of the unikernel net tower: the RFC 1071 internet checksum
// and scalar address representations that every layer above (eth, arp,
// ipv4, icmp, udp, tcp) needs.
//
// PURE — no FFI, no sockets, no clock. Everything here is a total
// function over bytes and integers, so it is unit-testable offline and
// linkable into a freestanding target.
//
// ADDRESS REPRESENTATION
//
//   IPv4 address → `i`, host order, low 32 bits. 10.0.2.15 is
//                  0x0A00020F. Zero is "unspecified", not a valid host.
//   MAC address  → `i`, low 48 bits, first wire byte most significant.
//                  02:00:00:00:00:01 is 0x020000000001.
//
// Scalars, deliberately: addresses are copied, compared and stored in
// tables constantly, and a `( Vec u )` for each would mean an owned
// allocation per lookup plus the ownership dance on every match arm.
// Fixed-width identities are values, not buffers.
//
// OWNERSHIP: everything in this module is a scalar except `ipv4_str`
// and `mac_str`, which return a `String` — a manually-managed handle
// (docs/MEMORY.md §7.4). The caller frees it with `string_free`. Both
// are diagnostic helpers; nothing on the packet hot path allocates.
//
// CHECKSUM
//
//   `inet_sum` accumulates a 32-bit one's-complement sum over a byte
//   range; `inet_sum_add`/`inet_sum_u16` extend one over non-contiguous
//   data (a TCP/UDP pseudo-header is not adjacent to its payload), and
//   `inet_fold` collapses the accumulator to 16 bits. Splitting the
//   accumulation from the folding is what makes the pseudo-header case
//   work without building a temporary buffer.
//
//   The sum is endian-agnostic in the classic way: it is computed on
//   big-endian 16-bit words and stored big-endian, so a receiver that
//   sums the whole datagram including the checksum field gets 0xFFFF.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── checksum ─────────────────────────────────────────────────────

// Accumulate the big-endian 16-bit words of v[off .. off+len) into an
// existing 32-bit accumulator. A trailing odd byte is padded on the
// right with zero, per RFC 1071 §1.
@ inet_sum_add i acc ( Vec u ) v i off i len → i {
    : ~ i s acc
    : ~ i k 0
    ~ <= + k 2 len {
        : i hi ?? ( vec_get [u] v + off k ) { T b → # i b F → 0 }
        : i lo ?? ( vec_get [u] v + off + k 1 ) { T b → # i b F → 0 }
        = s + s | << hi 8 lo
        = k + k 2
    }
    ? == & len 1 1 {
        : i hi ?? ( vec_get [u] v + off - len 1 ) { T b → # i b F → 0 }
        = s + s << hi 8
    } {}
    ^ s
}

// Accumulate a single 16-bit value (pseudo-header fields).
@ inet_sum_u16 i acc i x → i { ^ + acc & x 65535 }

// Accumulate a 32-bit value as two 16-bit words (pseudo-header addrs).
@ inet_sum_u32 i acc i x → i { ^ + + acc & >> x 16 65535 & x 65535 }

// Sum a byte range from scratch.
@ inet_sum ( Vec u ) v i off i len → i { ^ ( inet_sum_add 0 v off len ) }

// Collapse carries into 16 bits.
@ inet_fold i acc → i {
    : ~ i x acc
    ~ > x 65535 { = x + & x 65535 >> x 16 }
    ^ x
}

// Final checksum from an accumulator: fold, then one's complement.
@ inet_finish i acc → i { ^ ^^ ( inet_fold acc ) 65535 }

// One-shot checksum over a byte range.
@ inet_checksum ( Vec u ) v i off i len → i { ^ ( inet_finish ( inet_sum v off len ) ) }

// ── IPv4 addresses ───────────────────────────────────────────────

@ ipv4_make i a i b i c i d → i {
    ^ | | | << & a 255 24 << & b 255 16 << & c 255 8 & d 255
}

@ ipv4_octet i addr i n → i { ^ & >> addr * 8 - 3 n 255 }

// Dotted-quad → address. Strict: exactly four decimal octets, each
// 0..255, no leading '+'/'-', no empty component, nothing trailing.
// Strictness matters — a lax parser here turns a typo in a relay
// address into a silent connection to the wrong host.
@ ipv4_parse s text → ?i {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ @ ?i { F 0 } } {}
    : ~ i acc 0
    : ~ i octet 0
    : ~ i digits 0
    : ~ i parts 0
    : ~ b ok T
    : ~ i k 0
    ~ && ok < k n {
        : i c ( nurl_str_at text n k )
        ? == c 46 {
            // '.' — close the current octet
            ? || == digits 0 == parts 3 { = ok F } {
                = acc | << acc 8 octet
                = parts + parts 1
                = octet 0
                = digits 0
            }
        } {
            ? && >= c 48 <= c 57 {
                = octet + * octet 10 - c 48
                = digits + digits 1
                // >3 digits or >255 is malformed; both are rejected here
                ? || > digits 3 > octet 255 { = ok F } {}
            } { = ok F }
        }
        = k + k 1
    }
    ? || ! ok || == digits 0 != parts 3 { ^ @ ?i { F 0 } } {}
    = acc | << acc 8 octet
    ^ @ ?i { T acc }
}

@ ipv4_str i addr → String {
    : String out ( string_new )
    : ~ i g 0
    ~ < g 4 {
        ? > g 0 { ( string_push_str out `.` ) } {}
        ( string_push_int out ( ipv4_octet addr g ) )
        = g + g 1
    }
    ^ out
}

// Is `addr` inside the network `net`/`mask` (both host-order)?
@ ipv4_in_subnet i addr i net i mask → b { ^ == & addr mask & net mask }

// 224.0.0.0/4
@ ipv4_is_multicast i addr → b { ^ == & addr 4026531840 3758096384 }

@ ipv4_is_broadcast i addr → b { ^ == addr 4294967295 }

// 127.0.0.0/8
@ ipv4_is_loopback i addr → b { ^ == & addr 4278190080 2130706432 }

// Is this an address a host can call its own? Zero is "no address", the
// loopback block belongs to the machine's own stack, and multicast and
// broadcast are destinations rather than identities. Every one of them
// is something a DHCP server can put in `yiaddr`, and a host that
// accepts one has configured itself off the network — silently, because
// nothing fails until the first packet nobody answers.
@ ipv4_is_assignable i addr → b {
    ? == addr 0 { ^ F } {}
    ? ( ipv4_is_loopback addr ) { ^ F } {}
    ? ( ipv4_is_multicast addr ) { ^ F } {}
    ? ( ipv4_is_broadcast addr ) { ^ F } {}
    ^ T
}

// A netmask is a run of ones followed by a run of zeros — nothing else
// is a mask, and the arithmetic underneath `ipv4_in_subnet` and
// `ipv4_subnet_broadcast` quietly means something else if it is handed
// one that is not. `mask | (mask - 1)` is all-ones exactly when the
// zeros are a suffix; zero itself is not a usable mask here.
@ ipv4_mask_is_contiguous i mask → b {
    ? == mask 0 { ^ F } {}
    ? == mask 4294967295 { ^ T } {}
    ^ == & | mask - mask 1 4294967295 4294967295
}

// The all-ones directed broadcast for a subnet, e.g. 10.0.2.255.
@ ipv4_subnet_broadcast i net i mask → i {
    ^ | & net mask & ^^ mask 4294967295 4294967295
}

// Prefix length → mask. 24 → 255.255.255.0. Out-of-range clamps.
@ ipv4_mask_from_prefix i bits → i {
    ? <= bits 0 { ^ 0 } {}
    ? >= bits 32 { ^ 4294967295 } {}
    ^ & << 4294967295 - 32 bits 4294967295
}

// ── MAC addresses ────────────────────────────────────────────────

@ mac_broadcast → i { ^ 281474976710655 }

@ mac_is_broadcast i mac → b { ^ == mac 281474976710655 }

// A multicast MAC has the low bit of the first octet set.
@ mac_is_multicast i mac → b { ^ == & >> mac 40 1 1 }

@ mac_octet i mac i n → i { ^ & >> mac * 8 - 5 n 255 }

@ __hexdig i c → i {
    ? && >= c 48 <= c 57 { ^ - c 48 } {}
    ? && >= c 97 <= c 102 { ^ - c 87 } {}
    ? && >= c 65 <= c 70 { ^ - c 55 } {}
    ^ -1
}

// "02:00:00:00:00:01" → 0x020000000001. Accepts ':' or '-' separators
// and either case; requires exactly six two-digit groups.
@ mac_parse s text → ?i {
    : i n ( nurl_str_len text )
    ? != n 17 { ^ @ ?i { F 0 } } {}
    : ~ i acc 0
    : ~ b ok T
    : ~ i g 0
    ~ && ok < g 6 {
        : i base * g 3
        : i hi ( __hexdig ( nurl_str_at text n base ) )
        : i lo ( __hexdig ( nurl_str_at text n + base 1 ) )
        ? || < hi 0 < lo 0 { = ok F } { = acc | << acc 8 | << hi 4 lo }
        ? < g 5 {
            : i sep ( nurl_str_at text n + base 2 )
            ? && != sep 58 != sep 45 { = ok F } {}
        } {}
        = g + g 1
    }
    ? ! ok { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T acc }
}

@ __hexchar i v → i { ^ ? < v 10 + 48 v + 87 v }

@ mac_str i mac → String {
    : String out ( string_new )
    : ~ i g 0
    ~ < g 6 {
        ? > g 0 { ( string_push_str out `:` ) } {}
        : i o ( mac_octet mac g )
        ( string_push_char out ( __hexchar >> o 4 ) )
        ( string_push_char out ( __hexchar & o 15 ) )
        = g + g 1
    }
    ^ out
}
