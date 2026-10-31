// call_join_handed_to_a_reader: as h725, the arms calls that build the struct: the join knew its
// arms owned what they yielded (mem_arm_hown), and the call never asked.
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
// map: §7.6 | A2 | runs-clean | h728 | agora #174: the same with calls in the arms: the join's ownership bit was never asked
$ `stdlib/core/string.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ mks i p → S { ^ @ S { ( mk ) p } }

@ use S h → i { ^ ( string_len . h s ) }

@ main → i {
    : ~ i n 0
    ~ < n 4 {
        ( nurl_println_int ( use ? == 0 % n 2 ( mks 0 ) ( mks 1 ) ) )
        = n + n 1
    }
    ^ 0
}
