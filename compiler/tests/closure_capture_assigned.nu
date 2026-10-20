// closure_capture_assigned.nu — a closure that assigns a `: ~` binding
// captures it by pointer, so the write reaches the binding.
//
// The everyday shapes: a callback that counts, sums, finds and flags
// (vec_each, range_each, a scan function of one's own), the `ok` flag a
// `recover` body sets on success, a closure nested in a closure assigning
// the outer binding, an i32 and a REAL accumulator, and a closure built
// once per loop iteration; then a String built up across calls, an option
// holding the largest, a result handed out of `recover`, and a Vec
// replaced. A closure that only READS a mutable binding still takes a
// snapshot of it (the last line: 3, not 100). Escaping such a closure is
// refused (borrow_escape_assigned_counter.nu,
// borrow_escape_assigned_handle.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/iter.nu`
$ `stdlib/core/string.nu`

@ scan ( Vec i ) xs ( @ b i ) f → v {
    ~ x xs { ? ! ( f x ) { ^ } {} }
}

@ risky i x → v { ? > x 2 { ( panic `too big` ) } {} }

@ tenfold i k → !i String { ? > k 2 { ( panic `too big` ) } {} ^ @ !i String { T * k 10 } }

@ main → i {
    : ( Vec i ) nums ( vec_new [i] )
    ( vec_push [i] nums 3 ) ( vec_push [i] nums 4 ) ( vec_push [i] nums 5 ) ( vec_push [i] nums 6 )

    : ~ i n 0
    : ~ i sum 0
    : ~ b seen F
    ( vec_each [i] nums \ i x → v {
        = n + n 1
        = sum + sum x
        ? == x 4 { = seen T } {}
    } )
    ( nurl_println ( nurl_str_cat `count ` ( nurl_str_int n ) ) )
    ( nurl_println ( nurl_str_cat `sum ` ( nurl_str_int sum ) ) )
    ( nurl_println ? seen `saw 4` `no 4` )

    // Stop at the first match, remembering where.
    : ~ i at -1
    : ~ i k 0
    ( scan nums \ i x → b {
        ? == % x 5 0 { = at k ^ F } {}
        = k + k 1
        ^ T
    } )
    ( nurl_println ( nurl_str_cat `first multiple of 5 at ` ( nurl_str_int at ) ) )

    // A float and an i32.
    : ~ f mean 0.0
    : ~ i32 small # i32 0
    ( range_each 1 5 \ i x → v {
        = mean + mean # f x
        = small + small # i32 x
    } )
    = mean / mean 4.0
    ( nurl_println ( nurl_str_cat `mean ` ( nurl_str_float mean ) ) )
    ( nurl_println ( nurl_str_cat `i32 sum ` ( nurl_str_int # i small ) ) )

    // recover: the flag says whether the body ran to its end.
    : ~ i good 0
    ~ x nums {
        : ~ b ok F
        : !v PanicInfo r ( recover \ → v {
            ( risky - x 2 )
            = ok T
        } )
        ?? r { T _ → {} F p → { ( panic_info_free p ) } }
        ? ok { = good + good 1 } {}
    }
    ( nurl_println ( nurl_str_cat `ran clean ` ( nurl_str_int good ) ) )

    // A closure inside a closure, assigning the outer binding.
    : ~ i deep 0
    ( vec_each [i] nums \ i x → v {
        ( range_each 0 x \ i y → v { = deep + deep 1 } )
    } )
    ( nurl_println ( nurl_str_cat `nested ` ( nurl_str_int deep ) ) )

    // A String built up, an option kept, a result handed out, a Vec replaced.
    : ~ String acc ( string_from `` )
    ( vec_each [i] nums \ i x → v { = acc ( string_concat acc ( string_from ( nurl_str_int x ) ) ) } )
    ( nurl_println ( nurl_str_cat `digits ` ( string_data acc ) ) )
    : ~ ? i best @ ?i { F }
    ( vec_each [i] nums \ i x → v {
        = best ?? best { T b → ? > x b @ ?i { T x } @ ?i { T b } F → @ ?i { T x } }
    } )
    ( nurl_println ( nurl_str_cat `largest ` ( nurl_str_int ?? best { T b → b F → -1 } ) ) )
    : ~ i got 0
    : ~ i lost 0
    : ~ i j 0
    ~ < j 5 {
        : ~ ! i String out @ !i String { F ( string_from `did not run` ) }
        : !v PanicInfo r2 ( recover \ → v { = out ( tenfold j ) } )
        ?? r2 { T _ → {} F p → { ( panic_info_free p ) } }
        ?? out { T v → { = got + got v } F e → { = lost + lost 1 } }
        = j + j 1
    }
    ( nurl_println ( nurl_str_cat `results ` ( nurl_str_cat ( nurl_str_int got ) ( nurl_str_cat ` ` ( nurl_str_int lost ) ) ) ) )
    : ~ ( Vec i ) last ( vec_new [i] )
    ( vec_each [i] nums \ i x → v { ? == x 4 { = last ( vec_new [i] ) ( vec_push [i] last 44 ) } {} } )
    ( nurl_println ( nurl_str_cat `replaced ` ( nurl_str_int ( vec_len [i] last ) ) ) )

    // A read-only capture is still a snapshot.
    : ~ i later 3
    : ( @ i ) peek \ → i { ^ later }
    = later 100
    ( nurl_println ( nurl_str_cat `snapshot ` ( nurl_str_int ( peek ) ) ) )
    ^ 0
}
