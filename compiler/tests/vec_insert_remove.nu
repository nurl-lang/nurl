// Test: stdlib/core/vec.nu — vec_insert / vec_remove
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ print_vec ( Vec i ) v → v {
    ( nurl_print `[` )
    : i n ( vec_len [i] v )
    : ~ i i 0
    ~ < i n {
        : ?i got ( vec_get [i] v i )
        ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] got 0 ) ) )
        ? < i - n 1 { ( nurl_print `,` ) } {}
        = i + i 1
    }
    ( nurl_print `]\n` )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 10 )
    ( vec_push [i] v 20 )
    ( vec_push [i] v 30 )
    ( nurl_print `start=` ) ( print_vec v )

    // Insert at head
    ( nurl_print `insert_head_ok=` )
    ( nurl_print ? ( vec_insert [i] v 0 5 ) `T` `F` )
    ( nurl_print ` → ` ) ( print_vec v )

    // Insert in middle
    ( vec_insert [i] v 2 15 )
    ( nurl_print `insert_mid → ` ) ( print_vec v )

    // Insert at end (idx == len) — equivalent to push
    : i len_now ( vec_len [i] v )
    ( vec_insert [i] v len_now 99 )
    ( nurl_print `insert_end → ` ) ( print_vec v )

    // Out-of-range insert
    ( nurl_print `insert_oor=` )
    ( nurl_print ? ( vec_insert [i] v 999 42 ) `T` `F` )
    ( nurl_print `\n` )

    ( nurl_print `negative_oor=` )
    ( nurl_print ? ( vec_insert [i] v -1 42 ) `T` `F` )
    ( nurl_print `\n` )

    // Remove from head
    : ?i r0 ( vec_remove [i] v 0 )
    ( nurl_print `removed_head=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] r0 -1 ) ) )
    ( nurl_print ` → ` ) ( print_vec v )

    // Remove from middle
    : ?i r1 ( vec_remove [i] v 1 )
    ( nurl_print `removed_mid=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] r1 -1 ) ) )
    ( nurl_print ` → ` ) ( print_vec v )

    // Remove last
    : i last_idx - ( vec_len [i] v ) 1
    : ?i rl ( vec_remove [i] v last_idx )
    ( nurl_print `removed_last=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] rl -1 ) ) )
    ( nurl_print ` → ` ) ( print_vec v )

    // Out-of-range remove
    : ?i oob ( vec_remove [i] v 99 )
    ( nurl_print `remove_oob_none=` )
    ?? oob {
        T x → ( nurl_print `NO\n` )
        F → ( nurl_print `YES\n` )
    }

    // Empty Vec edge: insert at 0 then remove at 0
    : ( Vec i ) e ( vec_new [i] )
    ( vec_insert [i] e 0 7 )
    ( nurl_print `empty_insert → ` ) ( print_vec e )
    : ?i re ( vec_remove [i] e 0 )
    ( nurl_print `empty_remove=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] re -1 ) ) )
    ( nurl_print ` len=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] e ) ) )
    ( nurl_print `\n` )

    ( vec_free [i] e )
    ( vec_free [i] v )
    ( nurl_print `done\n` )
    ^ 0
}
