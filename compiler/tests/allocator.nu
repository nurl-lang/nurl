// Allocator test — alloc, realloc, zalloc, memcpy

@ main → i {
    ( nurl_print `Allocator test...\n` )

    // Allocate 5 × i64 (40 bytes), fill 0 10 20 30 40
    : s buf ( nurl_alloc * 5 8 )
    ( nurl_poke buf 0 0 )
    ( nurl_poke buf 1 10 )
    ( nurl_poke buf 2 20 )
    ( nurl_poke buf 3 30 )
    ( nurl_poke buf 4 40 )

    ( nurl_print `filled: ` )
    : i n 0
    ~ < n 5 {
        ( nurl_print ( nurl_str_int ( nurl_peek buf n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )

    // Realloc to 10 × i64 (80 bytes), fill new slots 50..90
    : s buf2 ( nurl_realloc buf * 10 8 )
    ( nurl_poke buf2 5 50 )
    ( nurl_poke buf2 6 60 )
    ( nurl_poke buf2 7 70 )
    ( nurl_poke buf2 8 80 )
    ( nurl_poke buf2 9 90 )

    ( nurl_print `after realloc: ` )
    = n 0
    ~ < n 10 {
        ( nurl_print ( nurl_str_int ( nurl_peek buf2 n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )

    // Zero-initialised allocation of 5 × i64
    : s zbuf ( nurl_zalloc * 5 8 )
    ( nurl_print `zeroed: ` )
    = n 0
    ~ < n 5 {
        ( nurl_print ( nurl_str_int ( nurl_peek zbuf n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )

    // memcpy first 5 elements of buf2 into zbuf
    ( nurl_memcpy zbuf buf2 * 5 8 )
    ( nurl_print `after memcpy: ` )
    = n 0
    ~ < n 5 {
        ( nurl_print ( nurl_str_int ( nurl_peek zbuf n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )

    ( nurl_free buf2 )
    ( nurl_free zbuf )

    ( nurl_print `done\n` )
    ^ 0
}
