// bytes_endian.nu — fixed-width integer load/store over Vec[u].
//
// Covers u16 / u32 / u64 in both byte orders + bounds violations on
// reads. Round-trip pattern: push N bytes → read them back → confirm
// the value equals what we started with.

$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`

@ print_u16 s tag u16 n → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int # i n ) )
    ( nurl_print `\n` )
}

@ print_u32 s tag u32 n → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int # i n ) )
    ( nurl_print `\n` )
}

@ print_u64 s tag u64 n → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int # i n ) )
    ( nurl_print `\n` )
}

@ print_byte s tag u b → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int # i b ) )
    ( nurl_print `\n` )
}

@ main → i {
    // ── u16 ──────────────────────────────────────────────────────
    : ( Vec u ) buf16 ( vec_new [u] )
    ( bytes_push_u16_be buf16 # u16 4660 )  // 0x1234
    ( bytes_push_u16_le buf16 # u16 4660 )
    ( nurl_print `u16 len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] buf16 ) ) ) ( nurl_print `\n` )
    : ?u b16_0 ( vec_get [u] buf16 0 )
    : ?u b16_1 ( vec_get [u] buf16 1 )
    : ?u b16_2 ( vec_get [u] buf16 2 )
    : ?u b16_3 ( vec_get [u] buf16 3 )
    ?? b16_0 { T b → ( print_byte `u16_be[0]` b ) F → {} }  // 0x12 = 18
    ?? b16_1 { T b → ( print_byte `u16_be[1]` b ) F → {} }  // 0x34 = 52
    ?? b16_2 { T b → ( print_byte `u16_le[0]` b ) F → {} }  // 0x34 = 52
    ?? b16_3 { T b → ( print_byte `u16_le[1]` b ) F → {} }  // 0x12 = 18
    : ?u16 r16_be ( bytes_read_u16_be buf16 0 )
    : ?u16 r16_le ( bytes_read_u16_le buf16 2 )
    ?? r16_be { T n → ( print_u16 `r_u16_be` n ) F → ( nurl_print `r_u16_be=None\n` ) }
    ?? r16_le { T n → ( print_u16 `r_u16_le` n ) F → ( nurl_print `r_u16_le=None\n` ) }

    // Boundary value: u16 max 65535 = 0xFFFF
    : ( Vec u ) maxbuf ( vec_new [u] )
    ( bytes_push_u16_be maxbuf # u16 65535 )
    : ?u16 rmax ( bytes_read_u16_be maxbuf 0 )
    ?? rmax { T n → ( print_u16 `r_u16_max` n ) F → ( nurl_print `r_u16_max=None\n` ) }
    ( vec_free [u] maxbuf )
    ( vec_free [u] buf16 )

    // ── u32 ──────────────────────────────────────────────────────
    : ( Vec u ) buf32 ( vec_new [u] )
    ( bytes_push_u32_be buf32 # u32 305419896 )  // 0x12345678
    ( bytes_push_u32_le buf32 # u32 305419896 )
    ( nurl_print `u32 len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] buf32 ) ) ) ( nurl_print `\n` )
    : ?u b32_0 ( vec_get [u] buf32 0 )
    : ?u b32_3 ( vec_get [u] buf32 3 )
    : ?u b32_4 ( vec_get [u] buf32 4 )
    : ?u b32_7 ( vec_get [u] buf32 7 )
    ?? b32_0 { T b → ( print_byte `u32_be[0]` b ) F → {} }  // 0x12 = 18
    ?? b32_3 { T b → ( print_byte `u32_be[3]` b ) F → {} }  // 0x78 = 120
    ?? b32_4 { T b → ( print_byte `u32_le[0]` b ) F → {} }  // 0x78 = 120
    ?? b32_7 { T b → ( print_byte `u32_le[3]` b ) F → {} }  // 0x12 = 18
    : ?u32 r32_be ( bytes_read_u32_be buf32 0 )
    : ?u32 r32_le ( bytes_read_u32_le buf32 4 )
    ?? r32_be { T n → ( print_u32 `r_u32_be` n ) F → ( nurl_print `r_u32_be=None\n` ) }
    ?? r32_le { T n → ( print_u32 `r_u32_le` n ) F → ( nurl_print `r_u32_le=None\n` ) }

    // u32 high-bit-set value: 0x80000001 = 2147483649 (won't fit in i32)
    : ( Vec u ) buf32hi ( vec_new [u] )
    ( bytes_push_u32_be buf32hi # u32 2147483649 )
    : ?u32 rhi ( bytes_read_u32_be buf32hi 0 )
    ?? rhi { T n → ( print_u32 `r_u32_hi` n ) F → ( nurl_print `r_u32_hi=None\n` ) }
    ( vec_free [u] buf32hi )
    ( vec_free [u] buf32 )

    // ── u64 ──────────────────────────────────────────────────────
    // 0x0123456789ABCDEF = 81985529216486895
    : ( Vec u ) buf64 ( vec_new [u] )
    ( bytes_push_u64_be buf64 # u64 81985529216486895 )
    ( bytes_push_u64_le buf64 # u64 81985529216486895 )
    ( nurl_print `u64 len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] buf64 ) ) ) ( nurl_print `\n` )
    : ?u b64_0 ( vec_get [u] buf64 0 )
    : ?u b64_7 ( vec_get [u] buf64 7 )
    : ?u b64_8 ( vec_get [u] buf64 8 )
    : ?u b64_15 ( vec_get [u] buf64 15 )
    ?? b64_0 { T b → ( print_byte `u64_be[0]` b ) F → {} }  // 0x01 = 1
    ?? b64_7 { T b → ( print_byte `u64_be[7]` b ) F → {} }  // 0xEF = 239
    ?? b64_8 { T b → ( print_byte `u64_le[0]` b ) F → {} }  // 0xEF = 239
    ?? b64_15 { T b → ( print_byte `u64_le[7]` b ) F → {} }  // 0x01 = 1
    : ?u64 r64_be ( bytes_read_u64_be buf64 0 )
    : ?u64 r64_le ( bytes_read_u64_le buf64 8 )
    ?? r64_be { T n → ( print_u64 `r_u64_be` n ) F → ( nurl_print `r_u64_be=None\n` ) }
    ?? r64_le { T n → ( print_u64 `r_u64_le` n ) F → ( nurl_print `r_u64_le=None\n` ) }
    ( vec_free [u] buf64 )

    // ── Out-of-range read returns None ───────────────────────────
    : ( Vec u ) tiny ( vec_new [u] )
    ( vec_push [u] tiny # u 7 )
    : ?u16 oob16 ( bytes_read_u16_be tiny 0 )
    ?? oob16 {
        T n → ( nurl_print `oob_u16=Some\n` )
        F → ( nurl_print `oob_u16=None\n` )
    }
    : ?u32 oob32 ( bytes_read_u32_le tiny 0 )
    ?? oob32 {
        T n → ( nurl_print `oob_u32=Some\n` )
        F → ( nurl_print `oob_u32=None\n` )
    }
    : ?u64 oob64 ( bytes_read_u64_be tiny 0 )
    ?? oob64 {
        T n → ( nurl_print `oob_u64=Some\n` )
        F → ( nurl_print `oob_u64=None\n` )
    }
    // Negative offset also rejected.
    : ?u16 neg ( bytes_read_u16_be tiny -1 )
    ?? neg {
        T n → ( nurl_print `neg_u16=Some\n` )
        F → ( nurl_print `neg_u16=None\n` )
    }
    ( vec_free [u] tiny )

    ( nurl_print `done\n` )
    ^ 0
}
