// Test: typed alloc/zalloc from stdlib/core/mem.nu
$ `stdlib/core/mem.nu`

@ main → i {
    ( nurl_print `typed alloc:\n` )

    // alloc[i] 5: uninitialised i64 buffer, fill with 0,10,20,30,40
    : *i buf ( alloc [i] 5 )
    : i n 0
    ~ < n 5 {
        ( nurl_poke #s buf n * n 10 )
        = n + n 1
    }
    ( nurl_print `filled: ` )
    = n 0
    ~ < n 5 {
        ( nurl_print ( nurl_str_int ( nurl_peek #s buf n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )
    ( nurl_free #s buf )

    // zalloc[i] 5: zero-initialised, expect all zeros
    : *i zbuf ( zalloc [i] 5 )
    ( nurl_print `zeroed: ` )
    = n 0
    ~ < n 5 {
        ( nurl_print ( nurl_str_int ( nurl_peek #s zbuf n ) ) )
        ( nurl_print ` ` )
        = n + n 1
    }
    ( nurl_print `\n` )
    ( nurl_free #s zbuf )

    ( nurl_print `done\n` )
    ^ 0
}
