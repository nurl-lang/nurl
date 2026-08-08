// net_inet.nu — offline test for stdlib/net/inet.nu. Deterministic: RFC 1071
// checksum against a real IPv4 header capture, plus the address parsers'
// accept/reject boundaries. No sockets, no clock.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ hex s h → ( Vec u ) {
    ^ ?? ( bytes_from_hex h ) { T v → v F e → ( vec_new [u] ) }
}

@ main → i {
    // ── RFC 1071 checksum, real IPv4 header ──────────────────────
    // 45 00 00 73 00 00 40 00 40 11 c0a80001 c0a800c7, checksum b861.
    // Header with the checksum field zeroed → the checksum must come
    // out as 0xb861.
    : ( Vec u ) hdr ( hex `450000730000400040110000c0a80001c0a800c7` )
    ( pb `ipv4 header checksum = 0xb861: ` == ( inet_checksum hdr 0 20 ) 47201 )

    // Verification property: summing the header *including* a correct
    // checksum folds to 0xffff. This is the receive-side check, and it
    // is a different code path than generation — worth its own case.
    : ( Vec u ) hdr2 ( hex `45000073000040004011b861c0a80001c0a800c7` )
    ( pb `verify folds to 0xffff: ` == ( inet_fold ( inet_sum hdr2 0 20 ) ) 65535 )

    // Odd length: trailing byte is right-padded with zero.
    : ( Vec u ) odd ( hex `0102030405` )
    // 0x0102 + 0x0304 + 0x0500 = 0x0906 → complement 0xf6f9
    ( pb `odd-length pad: ` == ( inet_checksum odd 0 5 ) 63225 )

    // Empty range sums to zero → checksum 0xffff.
    ( pb `empty range: ` == ( inet_checksum odd 0 0 ) 65535 )

    // Carry folding: two words that overflow 16 bits.
    // 0xffff + 0xffff = 0x1fffe → fold → 0xffff → complement 0
    : ( Vec u ) carry ( hex `ffffffff` )
    ( pb `carry folds: ` == ( inet_checksum carry 0 4 ) 0 )

    // Incremental accumulation must equal one-shot over the whole
    // buffer — this is what makes pseudo-header checksums possible.
    : i split ( inet_sum_add ( inet_sum hdr 0 8 ) hdr 8 12 )
    ( pb `split sum == one-shot: ` == ( inet_finish split ) ( inet_checksum hdr 0 20 ) )

    // Pseudo-header helpers accumulate the same way as raw bytes would.
    // u32 0xc0a80001 == bytes c0 a8 00 01.
    : ( Vec u ) a4 ( hex `c0a80001` )
    ( pb `sum_u32 == byte sum: ` == ( inet_sum_u32 0 3232235521 ) ( inet_sum a4 0 4 ) )
    : ( Vec u ) p16 ( hex `0011` )
    ( pb `sum_u16 == byte sum: ` == ( inet_sum_u16 0 17 ) ( inet_sum p16 0 2 ) )

    // Vec is a manually-managed handle (docs/MEMORY.md §7.4) — freeing
    // here keeps this test clean under LSAN_DETECT_LEAKS=1.
    ( vec_free [u] hdr ) ( vec_free [u] hdr2 ) ( vec_free [u] odd )
    ( vec_free [u] carry ) ( vec_free [u] a4 ) ( vec_free [u] p16 )

    // ── IPv4 addresses ───────────────────────────────────────────
    ( pb `make 10.0.2.15: ` == ( ipv4_make 10 0 2 15 ) 167772687 )
    ( pb `octet 0: ` == ( ipv4_octet ( ipv4_make 10 0 2 15 ) 0 ) 10 )
    ( pb `octet 3: ` == ( ipv4_octet ( ipv4_make 10 0 2 15 ) 3 ) 15 )
    : String astr ( ipv4_str ( ipv4_make 192 168 1 200 ) )
    // nurl_str_eq returns a C-style i (0/1), and pb's parameter is a
    // contract-typed b — write the comparison out (the compiler now
    // rejects the silent int→bool narrowing at call sites).
    ( pb `str round-trip: ` != 0 ( nurl_str_eq ( string_data astr ) `192.168.1.200` ) )
    ( string_free astr )

    ( pb `parse 10.0.2.15: ` ?? ( ipv4_parse `10.0.2.15` ) { T a → == a 167772687 F → F } )
    ( pb `parse 0.0.0.0: ` ?? ( ipv4_parse `0.0.0.0` ) { T a → == a 0 F → F } )
    ( pb `parse 255.255.255.255: ` ?? ( ipv4_parse `255.255.255.255` ) { T a → == a 4294967295 F → F } )

    // Rejections — a lax parser here would silently connect elsewhere.
    ( pb `reject 256.0.0.1: ` ?? ( ipv4_parse `256.0.0.1` ) { T a → F F → T } )
    ( pb `reject 1.2.3: ` ?? ( ipv4_parse `1.2.3` ) { T a → F F → T } )
    ( pb `reject 1.2.3.4.5: ` ?? ( ipv4_parse `1.2.3.4.5` ) { T a → F F → T } )
    ( pb `reject 1.2.3.: ` ?? ( ipv4_parse `1.2.3.` ) { T a → F F → T } )
    ( pb `reject .1.2.3: ` ?? ( ipv4_parse `.1.2.3` ) { T a → F F → T } )
    ( pb `reject 1..2.3: ` ?? ( ipv4_parse `1..2.3` ) { T a → F F → T } )
    ( pb `reject empty: ` ?? ( ipv4_parse `` ) { T a → F F → T } )
    ( pb `reject 1.2.3.4x: ` ?? ( ipv4_parse `1.2.3.4x` ) { T a → F F → T } )
    ( pb `reject 0300.1.2.3: ` ?? ( ipv4_parse `0300.1.2.3` ) { T a → F F → T } )

    // ── subnets ──────────────────────────────────────────────────
    ( pb `mask /24: ` == ( ipv4_mask_from_prefix 24 ) 4294967040 )
    ( pb `mask /0: ` == ( ipv4_mask_from_prefix 0 ) 0 )
    ( pb `mask /32: ` == ( ipv4_mask_from_prefix 32 ) 4294967295 )
    ( pb `in subnet: ` ( ipv4_in_subnet ( ipv4_make 10 0 2 15 ) ( ipv4_make 10 0 2 0 ) 4294967040 ) )
    ( pb `not in subnet: ` ! ( ipv4_in_subnet ( ipv4_make 10 0 3 15 ) ( ipv4_make 10 0 2 0 ) 4294967040 ) )
    ( pb `subnet broadcast: ` == ( ipv4_subnet_broadcast ( ipv4_make 10 0 2 0 ) 4294967040 ) ( ipv4_make 10 0 2 255 ) )
    ( pb `is broadcast: ` ( ipv4_is_broadcast 4294967295 ) )
    ( pb `is multicast 224.0.0.251: ` ( ipv4_is_multicast ( ipv4_make 224 0 0 251 ) ) )
    ( pb `not multicast 10.0.0.1: ` ! ( ipv4_is_multicast ( ipv4_make 10 0 0 1 ) ) )

    // ── MAC ──────────────────────────────────────────────────────
    ( pb `parse mac: ` ?? ( mac_parse `02:00:00:00:00:01` ) { T m → == m 2199023255553 F → F } )
    ( pb `parse mac dashes: ` ?? ( mac_parse `02-00-00-00-00-01` ) { T m → == m 2199023255553 F → F } )
    ( pb `parse mac upper: ` ?? ( mac_parse `AA:BB:CC:DD:EE:FF` ) { T m → == m 187723572702975 F → F } )
    ( pb `reject short mac: ` ?? ( mac_parse `02:00:00:00:01` ) { T m → F F → T } )
    ( pb `reject bad sep: ` ?? ( mac_parse `02x00:00:00:00:01` ) { T m → F F → T } )
    ( pb `reject non-hex: ` ?? ( mac_parse `0g:00:00:00:00:01` ) { T m → F F → T } )
    : String mstr ( mac_str 2199023255553 )
    ( pb `mac str round-trip: ` ( nurl_str_eq ( string_data mstr ) `02:00:00:00:00:01` ) )
    ( string_free mstr )
    ( pb `mac octet 0: ` == ( mac_octet 2199023255553 0 ) 2 )
    ( pb `mac octet 5: ` == ( mac_octet 2199023255553 5 ) 1 )
    ( pb `broadcast mac: ` ( mac_is_broadcast ( mac_broadcast ) ) )
    ( pb `broadcast is multicast: ` ( mac_is_multicast ( mac_broadcast ) ) )
    ( pb `unicast not multicast: ` ! ( mac_is_multicast 2199023255553 ) )
    ^ 0
}
