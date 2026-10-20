// closure_capture_assigned_scalar.nu — a closure that assigns a `: ~`
// number or flag captures it by pointer, so the write reaches the binding.
//
// The everyday shapes: a callback that counts, sums, finds and flags
// (vec_each, range_each, a scan function of one's own), the `ok` flag a
// `recover` body sets on success, a closure nested in a closure assigning
// the outer binding, an i32 and a REAL accumulator, and a closure built
// once per loop iteration. A closure that only READS a mutable scalar still
// takes a snapshot of it (the last line: 3, not 100). Escaping such a
// closure is refused (borrow_escape_assigned_scalar.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/iter.nu`

@ scan ( Vec i ) xs ( @ b i ) f → v {
    ~ x xs { ? ! ( f x ) { ^ } {} }
}

@ risky i x → v { ? > x 2 { ( panic `too big` ) } {} }

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

    // A read-only capture is still a snapshot.
    : ~ i later 3
    : ( @ i ) peek \ → i { ^ later }
    = later 100
    ( nurl_println ( nurl_str_cat `snapshot ` ( nurl_str_int ( peek ) ) ) )
    ^ 0
}
