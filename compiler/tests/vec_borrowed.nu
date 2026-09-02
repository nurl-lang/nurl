// vec_borrowed.nu — borrowed Vec views (`vec_borrow_raw`) and the
// borrowed HTTP response body built on them.
//
// A borrowed view reads the caller's buffer in place, detaches into an
// owned copy on the first growth (copy-on-write), and its free releases
// only the handle. Each of those is checked against the SOURCE buffer,
// which must survive every operation on the view unchanged — under the
// sanitizer run this is also the proof that no view ever frees memory
// it does not own.
//
// Determinism: no clock, no socket, no env. ASan-clean.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http_response.nu`

@ label s name b v → v {
    ( nurl_print name )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

// 0,1,2,…,n-1 mod 256
@ ramp i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] v # u & k 255 )
        = k + k 1
    }
    ^ v
}

@ main → i {
    : ( Vec u ) src ( ramp 1000 )
    : *u sp ( vec_data [u] src )

    // ── read-through: same bytes, no copy ──
    : ( Vec u ) view ( vec_borrow_raw [u] sp 1000 )
    ( label `view_len_1000` == ( vec_len [u] view ) 1000 )
    ( label `view_cap_is_len` == ( vec_cap [u] view ) 1000 )
    ( label `view_data_is_source` == # i ( vec_data [u] view ) # i sp )
    ( label `view_eq_source` ( bytes_eq view src ) )
    ( label `view_get_7` ?? ( vec_get [u] view 7 ) { T x → == # i x 7 F → F } )

    // ── set_len: shrink allowed, growth refused ──
    ( label `set_len_grow_refused` ! ( vec_set_len [u] view 1001 ) )
    ( label `set_len_shrink_ok` ( vec_set_len [u] view 500 ) )
    ( label `view_len_500` == ( vec_len [u] view ) 500 )
    : b _r ( vec_set_len [u] view 1000 )  // refused: extent is 500 now
    ( label `view_len_still_500` == ( vec_len [u] view ) 500 )
    ( vec_free [u] view )
    ( label `source_intact_after_view_free` & == ( vec_len [u] src ) 1000 == # i . sp 999 231 )

    // ── copy-on-write: push detaches, source untouched ──
    : ( Vec u ) v2 ( vec_borrow_raw [u] sp 1000 )
    ( vec_push [u] v2 # u 42 )
    ( label `cow_len_1001` == ( vec_len [u] v2 ) 1001 )
    ( label `cow_detached` != # i ( vec_data [u] v2 ) # i sp )
    ( label `cow_kept_prefix` ?? ( vec_get [u] v2 999 ) { T x → == # i x 231 F → F } )
    ( label `cow_source_len_1000` == ( vec_len [u] src ) 1000 )
    ( vec_free [u] v2 )

    // ── clear + extend (the compressing-middleware shape) ──
    : ( Vec u ) v3 ( vec_borrow_raw [u] sp 1000 )
    ( vec_clear [u] v3 )
    ( bytes_extend_str v3 `gz` )
    ( label `clear_extend_len_2` == ( vec_len [u] v3 ) 2 )
    ( label `clear_extend_detached` != # i ( vec_data [u] v3 ) # i sp )
    ( label `clear_extend_source_byte0_still_0` == # i . sp 0 0 )
    ( vec_free [u] v3 )

    // ── shrink_to_fit on a view is a no-op; on a detached one it works ──
    : ( Vec u ) v4 ( vec_borrow_raw [u] sp 10 )
    ( vec_shrink_to_fit [u] v4 )
    ( label `shrink_noop_on_view` == # i ( vec_data [u] v4 ) # i sp )
    ( vec_reserve [u] v4 100 )
    ( vec_shrink_to_fit [u] v4 )
    ( label `shrink_after_detach_cap_len` == ( vec_cap [u] v4 ) 10 )
    ( vec_free [u] v4 )

    // ── empty / null views are ordinary empty owned Vecs ──
    : ( Vec u ) v5 ( vec_borrow_raw [u] sp 0 )
    ( label `empty_view_len_0` == ( vec_len [u] v5 ) 0 )
    ( vec_push [u] v5 # u 1 )
    ( label `empty_view_grows` == ( vec_len [u] v5 ) 1 )
    ( vec_free [u] v5 )

    // ── vec_borrow_into: an owned handle becomes a view, its old buffer released ──
    : ( Vec u ) v6 ( ramp 300 )
    ( vec_borrow_into [u] v6 sp 1000 )
    ( label `into_len_1000` == ( vec_len [u] v6 ) 1000 )
    ( label `into_data_is_source` == # i ( vec_data [u] v6 ) # i sp )
    ( vec_borrow_into [u] v6 sp 10 )  // view → view: nothing to free
    ( label `into_again_len_10` == ( vec_len [u] v6 ) 10 )
    ( vec_push [u] v6 # u 9 )  // detach
    ( vec_borrow_into [u] v6 sp 0 )  // owned → empty owned
    ( label `into_empty_len_0` == ( vec_len [u] v6 ) 0 )
    ( vec_free [u] v6 )

    // ── borrowed response body: identical wire bytes, nothing foreign freed ──
    : HttpResponse owned ( response_new 200 )
    ( response_set_header owned `Content-Type` `application/octet-stream` )
    ( response_set_body_bytes owned src )
    : HttpResponse borrowed ( response_new 200 )
    ( response_set_header borrowed `Content-Type` `application/octet-stream` )
    ( response_set_body_borrowed_bytes borrowed src )
    ( label `borrowed_body_is_source` == # i ( vec_data [u] . borrowed body ) # i sp )
    : ( Vec u ) w1 ( response_serialize owned )
    : ( Vec u ) w2 ( response_serialize borrowed )
    ( label `borrowed_wire_eq_owned` ( bytes_eq w1 w2 ) )
    ( label `wire_len_gt_body` > ( vec_len [u] w2 ) 1000 )
    ( vec_free [u] w1 )
    ( vec_free [u] w2 )
    // replacing a borrowed body with an owned one, and back, frees only what is owned
    ( response_set_body_str borrowed `x` )
    ( label `replaced_body_owned` != # i ( vec_data [u] . borrowed body ) # i sp )
    ( response_set_body_borrowed borrowed sp 1000 )
    ( http_response_free borrowed )
    ( http_response_free owned )
    ( label `source_intact_after_response_free` & == ( vec_len [u] src ) 1000 == # i . sp 500 244 )

    ( vec_free [u] src )
    ^ 0
}
