// simd_partial.nu — nurl_v128_ldn / nurl_v128_stn (docs/spec.md §4.1b),
// the partial-block load and store, on every length 0..20.
//
// ldn must return the first n bytes (16 past 16) and zero above them;
// stn must write exactly the first n bytes and nothing else. Each size
// class is two overlapping accesses (8, 4 or 1 byte wide), so the
// failures live at the class seams — 0, 1, 3, 4, 7, 8, 15, 16 — and at
// the overlap, which must carry identical bytes. The source of every
// load is an allocation of exactly n bytes, so under ASan a load that
// reads past it is a report, not a silent pass; the store lands between
// sentinel bytes that must survive.

$ `stdlib/core/vec.nu`

unsafe @ main → i {
    : ~ i fails 0
    : ~ i n 0
    ~ <= n 20 {
        : i m ? > n 16 16 n
        // ── ldn: the first m bytes, zero-padded ─────────────────────
        : ( Vec u ) src ( vec_with_cap [u] n )
        : ~ i k 0
        ~ < k n { ( vec_push [u] src # u + 17 * k 13 ) = k + k 1 }
        : ( Vec u ) out ( vec_zeroed [u] 16 )
        ( nurl_v128_st # s ( vec_data [u] out ) ( nurl_v128_ldn # s ( vec_data [u] src ) n ) )
        = k 0
        ~ < k 16 {
            : i want ? < k m + 17 * k 13 0
            ? != # i ( vec_at [u] out k ) & want 255 {
                ( nurl_print `ldn n=` ) ( nurl_print ( nurl_str_int n ) )
                ( nurl_print ` byte ` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `\n` )
                = fails + fails 1
            } {}
            = k + k 1
        }
        // ── stn: exactly the first m bytes, between sentinels ───────
        : ( Vec u ) dst ( vec_new [u] )
        = k 0
        ~ < k 40 { ( vec_push [u] dst # u 170 ) = k + k 1 }
        : v128 v ( nurl_v128_set32 0x04030201 0x08070605 0x0C0B0A09 0x100F0E0D )
        ( nurl_v128_stn # s + # i ( vec_data [u] dst ) 8 n v )
        = k 0
        ~ < k 40 {
            : i want ? & >= k 8 < k + 8 m - k 7 170
            ? != # i ( vec_at [u] dst k ) want {
                ( nurl_print `stn n=` ) ( nurl_print ( nurl_str_int n ) )
                ( nurl_print ` byte ` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `\n` )
                = fails + fails 1
            } {}
            = k + k 1
        }
        = n + n 1
    }
    ? == fails 0 { ( nurl_print `ldn / stn: every length agrees\n` ) } {}
    ^ fails
}
