// arm_local_struct_field_lent_by_the_tail_call_is_copied_runs_clean: `? c { : O lo @ O { … } ( first . lo name outer ) } …`: the tail call lends a field of the arm's own struct
// Closed: a field of one of the arm's own is the arm's own: copied where the call lends it, and the arm's locals go (agora #662).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #662: `? c { : O lo @ O { … } ( first . lo name outer ) } …`: the tail call lends a field of the arm's own struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → String { : ~ String r ( string_from `a heap string long enough for the buffer ` ) ( string_push_int r k ) ^ r }

@ idg [T] T x → T { ^ x }

@ first String a String b → String { ^ a }

@ pick String a String b b c → String { ^ ? c a b }

: O { String name i n }

@ f ( Vec String ) v String outer O o b c → i {
    : String e ? c { : O lo @ O { ( mk 2 ) 3 } ( first . lo name outer ) } ( mk 3 )
    ^ ( string_len e )
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk 9 ) )
    : String outer ( mk 8 )
    : O o @ O { ( mk 7 ) 1 }
    ^ - + ( f v outer o T ) ( f v outer o F ) + ( f v outer o T ) ( f v outer o F )
}
