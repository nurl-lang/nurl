// H691: as h690, the callee handing its argument back whole (`^ h`) into a
// binding: the result IS the join's value — it moves into the binding,
// which drops it (mem_lend_const `one`).
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ pass S h → S { ^ h }

@ main → i {
    : ~ i n 0
    ~ < n 4 {
        : S p ( pass ? == 0 % n 2 @ S { ( mk ) 0 } @ S { ( mk ) 1 } )
        ( nurl_println_int . p pad )
        = n + n 1
    }
    ^ 0
}
