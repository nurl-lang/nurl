// slice_bound_to_a_join_of_a_fresh_one_and_a_parameter_runs_clean: `: [i r ? > n 1 [i | 10 20 n] xs`
// Closed: the binding owns the buffer by the join's bit, its drop flag.
// main 6e45ef9: LeakSanitizer (strict): detected memory leaks (the fresh path).
// map: §7.6 | A2 | runs-clean | - | agora #664: a bound join
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n [i xs → i { : [i r ? > n 1 [i | 10 20 n] xs ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f 3 x ) 33 }
