// mutual_recursion_storing_a_view_of_a_local_string_in_an_inout_holder: the same cycle, whose base cases store a view of their String argument into the holder; one member hands the other a local String (agora #371's guard).
// Guard: the cycle's fixed point keeps that view in the holder (`0>1`), so handing a local String is refused.
// main 836c0e9: rejected.
// map: §2.7 | A2 | rejected | - | agora #371: a cycle storing a view of its String argument into an inout holder, handed a local
$ `stdlib/core/string.nu`

: W { s v }

@ ping inout W w String a i n → v {
    ? > n 0 {
        : String t ( string_from `a local string of ping` )
        ( pong w t - n 1 )
    } { = w @ W { ( string_data a ) } }
}

@ pong inout W w String a i n → v {
    ? > n 0 { ( ping w a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ main → i { : ~ W w @ W { `literal` } ( ping w ( string_from `an argument` ) 3 ) ( nurl_println . w v ) ^ 0 }
