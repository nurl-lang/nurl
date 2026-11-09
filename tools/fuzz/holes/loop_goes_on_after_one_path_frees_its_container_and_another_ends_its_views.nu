// loop_goes_on_after_one_path_frees_its_container_and_another_ends_its_views: agora #482 — `~ e b` over `b = ? c ( vec_at A 0 ) ( vec_at B 0 )`: one path clears `A` through a helper and continues, the other grows what `B`'s rows view
// Closed: an end of the element's views on one path no longer replaces an end of its storage on another (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop goes on after one path frees its container and another ends its views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec ( Vec ( Vec s ) ) ) v → v { ( vec_clear [( Vec ( Vec s ) )] v ) }

@ pick i n → b { ^ > n 0 }

@ main → i {
    : String keep ( string_from `a line that never changes, long enough` )
    : String line ( string_from `short` )
    : ( Vec ( Vec ( Vec s ) ) ) A ( vec_new [( Vec ( Vec s ) )] )
    : ~ ( Vec ( Vec s ) ) va ( vec_new [( Vec s )] )
    : ~ ( Vec s ) a0 ( vec_new [s] )
    ( vec_push [s] a0 ( string_data keep ) )
    ( vec_push [( Vec s )] va a0 )
    : ~ ( Vec s ) a1 ( vec_new [s] )
    ( vec_push [s] a1 ( string_data keep ) )
    ( vec_push [( Vec s )] va a1 )
    : ~ ( Vec s ) a2 ( vec_new [s] )
    ( vec_push [s] a2 ( string_data keep ) )
    ( vec_push [( Vec s )] va a2 )
    ( vec_push [( Vec ( Vec s ) )] A va )
    : ( Vec ( Vec ( Vec s ) ) ) B ( vec_new [( Vec ( Vec s ) )] )
    : ~ ( Vec ( Vec s ) ) vb ( vec_new [( Vec s )] )
    : ~ ( Vec s ) b0 ( vec_new [s] )
    ( vec_push [s] b0 ( string_data line ) )
    ( vec_push [( Vec s )] vb b0 )
    ( vec_push [( Vec ( Vec s ) )] B vb )
    : b c ( pick 1 )
    : ( Vec ( Vec s ) ) b ? c ( vec_at [( Vec ( Vec s ) )] A 0 ) ( vec_at [( Vec ( Vec s ) )] B 0 )
    : ~ i k 0
    : ~ i n 0
    ~ e b {
        = n + n ( vec_len [s] e )
        = k + k 1
        ? ( pick - 2 k ) { ( wipe A ) continue } {}
        ( string_push_str line ` and a long tail, so the buffer moves` )
    }
    ( nurl_println_int n )
    ^ 0
}
