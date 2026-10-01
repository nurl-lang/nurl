// wrap_of_maybe_lent_payload.nu — a returned option whose payload is lent on
// some runs only answers per call whether the caller owns it.
//
// `array_of` hands back its parameter (`^ @ ?Json { T doc }`, a lend) on one
// path and a payload of `( json_obj_get doc `data` )` on another — lent when
// that call lent it. The second path copied the payload unconditionally
// while the function counted as a lender, so the copy went to callers that
// never dropped it (the anomaly importer leaked one per parse).

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ array_of Json doc → ?Json {
    ? ( json_is_arr doc ) { ^ @ ?Json { T doc } } {}
    ? ( json_is_obj doc ) {
        ?? ( json_obj_get doc `data` ) {
            T v → { ? ( json_is_arr v ) { ^ @ ?Json { T v } } {} }
            F _ → {}
        }
    } {}
    ^ @ ?Json { F }
}

@ round Json d → i { ^ ?? ( array_of d ) { T a → ( json_arr_len a ) F → -1 } }

@ main → i {
    : Json d ( json_obj_new )
    : Json arr ( json_arr_new ) ( json_arr_push arr ( json_int 1 ) )
    ( json_obj_set d `data` arr )
    : Json d2 ( json_arr_new )
    : i a ( round d ) : i b ( round d2 )
    : i l - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i k 0 ~ < k 20 { : i x ( round d ) : i y ( round d2 ) = k + k 1 }
    : i g - - ( nurl_alloc_count ) ( nurl_free_count ) l
    ( nurl_println ( nurl_str_cat3 ( nurl_str_int a ) ` ` ( nurl_str_int b ) ) )
    ( nurl_println ? == g 0 `live allocations: steady` `live allocations grew` )
    ^ 0
}
