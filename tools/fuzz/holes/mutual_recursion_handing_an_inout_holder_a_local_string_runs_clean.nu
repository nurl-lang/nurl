// mutual_recursion_handing_an_inout_holder_a_local_string_runs_clean: two mutually recursive functions take an inout struct of a view and a String; one hands the other a local String, neither stores a view (agora #371's c3).
// Closed: parked walks that ask each other's answers settle them as their least fixed point (__bck_walk_scc): the cycle keeps nothing of either String in the holder, so handing it a local is safe. A cycle answered "may" before.
// main 4f15689: rejected ('w' is storage the caller holds …); safe on every input.
// map: §2.7 | A2 | runs-clean | - | agora #371: a cycle of two functions handing an inout holder a local String it never stores
$ `stdlib/core/string.nu`

: W { s v }

@ ping inout W w String a i n → v {
    ? > n 0 {
        : String t ( string_from `a local string of ping` )
        ( pong w t - n 1 )
    } {}
}

@ pong inout W w String a i n → v {
    ? > n 0 { ( ping w a - n 1 ) } {}
}

@ main → i { : ~ W w @ W { `literal` } ( ping w ( string_from `an argument` ) 3 ) ( nurl_println . w v ) ^ 0 }
