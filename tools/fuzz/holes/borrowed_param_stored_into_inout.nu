// borrowed_param_stored_into_inout: a parameter the function only borrows, assigned over an `inout` parameter (`= o b`), was stored as is: the caller's `x` and `a` then owned one buffer, freed twice, and the string `a` held before leaked.
// Closed: a borrowed parameter assigned over an `inout` place is copied in, and the place's old value is dropped (gen_assign) — as a borrowed handle stored into a struct field is.
// main (before this PR): heap-use-after-free in the caller.
// map: CallT.summary | A1 | runs-clean | h201 | borrowed String param assigned into inout param: caller's two names share buffer
$ `stdlib/core/string.nu`

@ put inout String o String b → v { = o b }

@ put_opt inout ? String o ? String b → v { = o b }

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap` )
    : String x ( string_from `a borrowed string, long enough for the heap` )
    ( put a x )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data x ) )
    : ~ ? String oa @ ?String { F }
    : ?String ox @ ?String { T ( string_from `a borrowed option, long enough for the heap` ) }
    ( put_opt oa ox )
    ( put_opt oa ox )
    ?? oa { T v → { ( nurl_println ( string_data v ) ) } F → {} }
    ^ 0
}
