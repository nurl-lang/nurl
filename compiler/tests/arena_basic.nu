$ `stdlib/std/arena.nu`

@ main → i {
    : Arena ar ( arena_with_cap 1024 )

    : *u p1 ( arena_alloc ar 100 )
    ( nurl_print `p1 nonnull=` ) ( nurl_print ? != 0 # i p1 `T` `F` )
    ( nurl_print ` used=` ) ( nurl_print ( nurl_str_int ( arena_used ar ) ) )
    ( nurl_print `\n` )

    : *u p2 ( arena_alloc ar 100 )
    : i diff - # i p2 # i p1
    ( nurl_print `p2-p1=` ) ( nurl_print ( nurl_str_int diff ) )
    ( nurl_print ` (expect 104 due to 8-byte align)` )
    ( nurl_print `\n` )

    : *u p3 ( arena_alloc ar 17 )
    : i p2_end + # i p2 100
    : i p2_end_aligned & + p2_end 7 -8
    : i diff3 - # i p3 # i p1
    : i expected_p3 - p2_end_aligned # i p1
    ( nurl_print `p3 offset=` ) ( nurl_print ( nurl_str_int diff3 ) )
    ( nurl_print ` expect=` ) ( nurl_print ( nurl_str_int expected_p3 ) )
    ( nurl_print `\n` )

    ( nurl_print `used=` ) ( nurl_print ( nurl_str_int ( arena_used ar ) ) )
    ( nurl_print ` cap=` ) ( nurl_print ( nurl_str_int ( arena_cap ar ) ) )
    ( nurl_print ` rem=` ) ( nurl_print ( nurl_str_int ( arena_remaining ar ) ) )
    ( nurl_print `\n` )

    : *u big ( arena_alloc ar 10000 )
    ( nurl_print `oom nonnull=` ) ( nurl_print ? != 0 # i big `T` `F` )
    ( nurl_print `\n` )

    ( arena_reset ar )
    ( nurl_print `after reset used=` ) ( nurl_print ( nurl_str_int ( arena_used ar ) ) )
    ( nurl_print ` cap=` ) ( nurl_print ( nurl_str_int ( arena_cap ar ) ) )
    ( nurl_print `\n` )

    : *u q ( arena_alloc ar 64 )
    : i q_off - # i q # i p1
    ( nurl_print `post-reset q offset=` ) ( nurl_print ( nurl_str_int q_off ) )
    ( nurl_print `\n` )

    : *u a16 ( arena_alloc_aligned ar 32 16 )
    : i a16_off - # i a16 # i p1
    : i mask16 15
    : i alignment_check & a16_off mask16
    ( nurl_print `aligned 16 check (0 means ok)=` ) ( nurl_print ( nurl_str_int alignment_check ) )
    ( nurl_print `\n` )

    ( arena_free ar )
    ( nurl_print `done\n` )
    ^ 0
}
