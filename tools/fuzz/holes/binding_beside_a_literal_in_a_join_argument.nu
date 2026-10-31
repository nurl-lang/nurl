// binding_beside_a_literal_in_a_join_argument: as h725, one arm a binding (lent: it stays the binding's), the
// other a literal (owned): dropped on the literal's path only, by the
// phi of the arms' bits.
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
// map: §7.6 | A2 | runs-clean | h730 | agora #174: a binding arm beside a literal arm: dropped on the literal's path only
$ `stdlib/core/string.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ use S h → i { ^ ( string_len . h s ) }

@ main → i {
    : S keep @ S { ( mk ) 5 }
    : ~ i n 0
    ~ < n 4 {
        ( nurl_println_int ( use ? == 0 % n 2 keep @ S { ( mk ) 1 } ) )
        = n + n 1
    }
    ( nurl_println_int ( use keep ) )
    ^ 0
}
