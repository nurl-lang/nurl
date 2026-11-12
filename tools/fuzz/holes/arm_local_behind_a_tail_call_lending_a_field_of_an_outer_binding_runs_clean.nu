// arm_local_behind_a_tail_call_lending_a_field_of_an_outer_binding_runs_clean: `? c { : String junk ( mk 2 ) ( idg [String] . o name ) } …`: the tail call lends a field of a parameter
// Closed: a field path an arm's tail call is handed is its root binding's: lent out of an outer one, it is none of the arm's own (agora #662).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #662: `? c { : String junk ( mk 2 ) ( idg [String] . o name ) } …`: the tail call lends a field of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → String { : ~ String r ( string_from `a heap string long enough for the buffer ` ) ( string_push_int r k ) ^ r }

@ idg [T] T x → T { ^ x }

@ first String a String b → String { ^ a }

: O { String name i n }

@ f ( Vec String ) v String outer O o b c → i {
    : String e ? c { : String junk ( mk 2 ) ( idg [String] . o name ) } ( mk 3 )
    ^ ( string_len e )
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk 9 ) )
    : String outer ( mk 8 )
    : O o @ O { ( mk 7 ) 1 }
    ^ - + ( f v outer o T ) ( f v outer o F ) + ( f v outer o T ) ( f v outer o F )
}
