// closure_capture_inout.nu — a closure that hands a captured `: ~` binding
// to an `inout` parameter changes it, as one that assigns it does, so it
// captures the binding by pointer (h298): a number the callee bumps, a
// String it grows or replaces, a struct field it is given, an argument
// past an operator expression. A binding the call only reads stays a
// snapshot, so a closure that runs on another thread may still read it.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

: Box { i n String s }

@ bump inout i n → v { = n + n 1 }

@ grow inout String s → v { ( string_push_str s `x` ) }

@ fresh inout String s → v { = s ( string_from `new` ) }

@ add_to i k inout i n → v { = n + n k }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 ) ( vec_push [i] xs 2 ) ( vec_push [i] xs 3 )
    : ~ i n 0
    ( vec_each [i] xs \ i x → v { ( bump n ) } )
    ( nurl_println ( nurl_str_cat `bumped ` ( nurl_str_int n ) ) )
    : ~ String s ( string_from `` )
    ( vec_each [i] xs \ i x → v { ( grow s ) } )
    ( nurl_println ( nurl_str_cat `grown ` ( string_data s ) ) )
    : ~ String t ( string_from `old` )
    ( vec_each [i] xs \ i x → v { ( fresh t ) } )
    ( nurl_println ( nurl_str_cat `replaced ` ( string_data t ) ) )
    : ~ Box b @ Box { 0 ( string_from `` ) }
    ( vec_each [i] xs \ i x → v { ( bump . b n ) ( fresh . b s ) } )
    ( nurl_println ( nurl_str_cat3 `field ` ( nurl_str_int . b n ) ( nurl_str_cat ` ` ( string_data . b s ) ) ) )
    : ~ i total 0
    ( vec_each [i] xs \ i x → v { ( add_to * x 10 total ) } )
    ( nurl_println ( nurl_str_cat `past an operator ` ( nurl_str_int total ) ) )
    // Read only: still a snapshot, so the closure may leave the frame.
    : ~ i step 5
    : !Thread ThreadErr th ( thread_spawn \ → v {
        : ~ i acc 0
        ( add_to step acc )
        ( nurl_println ( nurl_str_cat `thread ` ( nurl_str_int acc ) ) )
    } )
    ?? th { T h → { ( thread_join h ) } F _ → {} }
    ^ 0
}
