// closure_param_generic_struct.nu — a closure whose first parameter is
// of a generic struct type: `\ ( Slice u ) s → …`.
//
// `\` is both the closure marker and the try operator, and `\ ( … )`
// reads as a closure only when the parenthesised words begin a type. A
// generic struct's own name (Slice, Locked, a program's `Pair`) has no
// type entry until an instance of it is made, so `\ ( Slice u ) s → b`
// was taken for a try of the call `( Slice u )` ("use of undefined
// identifier 'u'"), while the same parameter second in the list, or in a
// function, was fine.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

: Pair [A] { A first A second }

@ each_window ( Vec u ) v ( @ b ( Slice u ) ) f → v {
    : ~ i k 0
    ~ < k ( vec_len [u] v ) {
        ? ! ( f ( slice_window [u] ( slice_from_vec [u] v ) k - ( vec_len [u] v ) k ) ) { ^ } {}
        = k + k 1
    }
}

@ main → i {
    : ( Vec u ) v ( vec_zeroed [u] 5 )
    : ~ i seen 0
    ( each_window v \ ( Slice u ) s → b { = seen + seen ( slice_len [u] s ) ^ T } )
    ( nurl_println ( nurl_str_cat `window bytes: ` ( nurl_str_int seen ) ) )
    : ( @ i ( Locked i ) ) peek \ ( Locked i ) l → i { ^ ( locked_get [i] l ) }
    : ( Locked i ) l ( locked_new [i] 41 )
    ( nurl_println ( nurl_str_cat `locked: ` ( nurl_str_int + 1 ( peek l ) ) ) )
    : ( @ i ( Pair i ) ) sum \ ( Pair i ) p → i { ^ + . p first . p second }
    ( nurl_println ( nurl_str_cat `pair: ` ( nurl_str_int ( sum @ ( Pair i ) { 2 3 } ) ) ) )
    ^ 0
}
