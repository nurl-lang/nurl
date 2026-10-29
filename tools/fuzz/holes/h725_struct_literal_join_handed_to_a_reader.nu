// H725: `( use ? c @ S { ( mk ) 0 } @ S { ( mk ) 1 } )` — a `?` join of two
// struct literals handed to a callee that only reads its argument. The
// literal in an arm is no argument of the call, so it published nothing
// for the call to drop, and nothing else did: each String leaked.
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ use S h → i { ^ ( string_len . h s ) }

@ main → i {
    : ~ i n 0
    ~ < n 4 {
        ( nurl_println_int ( use ? == 0 % n 2 @ S { ( mk ) 0 } @ S { ( mk ) 1 } ) )
        = n + n 1
    }
    ^ 0
}
