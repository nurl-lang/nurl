// inout_field_target_a_callee_hands_to_a_sink: `( f . h a )`, f taking its `inout` parameter and handing it to a `sink` (`( eat p )`); then the struct is dropped. Also a callee defined below its caller (the consumption is a module-end answer).
// Closed (agora #567): the field target was passed by address and the callee released its value, but the field stayed in its struct, which released it again at its drop. The field is now emptied after the call on the same answer that clears the drop flag of a binding handed over that way (a `z|` argument word, mem_drop_arg_temps); a read of it after the call is refused as before.
// main (before this PR): heap-use-after-free (SEGV) at h's drop.
// map: §7.6 | A2 | runs-clean | - | an inout field target its callee hands to a sink was released again by its struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } )
    ^ v
}

@ mkh → H { ^ @ H { ( mkv 1 ) ( mkv 2 ) } }

@ f inout ( Vec S ) p → i { ^ ( eat p ) }

@ main → i {
    : ~ H h ( mkh )
    : i x ( f . h a )
    : i y ( later . h b )
    ? != + x y 2 { ^ 1 } {}
    ^ 0
}

@ later inout ( Vec S ) p → i { ^ ( eat p ) }
