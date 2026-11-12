// arm_local_handed_to_a_tail_call_that_lends_another_argument_runs_clean: `? c { : String junk ( mk 2 ) ( first outer junk ) } …`: the tail call lends `outer`, not the arm's own `junk`
// Closed: an arm whose tail call is handed one of its own locals asks the callee, after the copy it makes where that local is lent, whether it lends anything the arm owns (mem_arm_outer_lend, after mem_arm_take_call); where it does not, the locals go at the arm's exit (agora #662).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #662: `? c { : String junk ( mk 2 ) ( first outer junk ) } …`: the tail call lends `outer`, not the arm's own `junk`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → String { : ~ String r ( string_from `a heap string long enough for the buffer ` ) ( string_push_int r k ) ^ r }

@ idg [T] T x → T { ^ x }

@ first String a String b → String { ^ a }

: O { String name i n }

@ f ( Vec String ) v String outer O o b c → i {
    : String e ? c { : String junk ( mk 2 ) ( first outer junk ) } ( mk 3 )
    ^ ( string_len e )
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk 9 ) )
    : String outer ( mk 8 )
    : O o @ O { ( mk 7 ) 1 }
    ^ - + ( f v outer o T ) ( f v outer o F ) + ( f v outer o T ) ( f v outer o F )
}
