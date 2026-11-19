// closure_moving_loop_hands_its_captures_elements_to_a_sink_runs_clean: AGORA-479 guard — a closure's `~ x t { ( eat x ) }` over its captured Vec, run twice: the loop moves each element out of the Vec, accepted
// map: §2.5 | A2 | runs-clean | - | AGORA-479 guard: a closure's moving `~` loop hands its captured Vec's elements to a sink, run twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `second string long enough for a heap buffer here` ) )
    : ( @ v ) wipe \ → v { ~ x t { ( eat x ) } }
    ( wipe )
    ( wipe )
    ^ 0
}
