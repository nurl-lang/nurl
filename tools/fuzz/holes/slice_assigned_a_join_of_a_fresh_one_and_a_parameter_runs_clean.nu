// slice_assigned_a_join_of_a_fresh_one_and_a_parameter_runs_clean: `: ~ [i r [i | 0]  = r ? > n 1 [i | 10 20 n] xs`
// Closed: a `: ~` slice has a drop flag from its `:`; gen_assign releases the old value by it and sets it by the right-hand side — here the join's bit (__last_slice_own_bit__).
// main 6e45ef9: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #664: an assigned join
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n [i xs → i { : ~ [i r [i | 0] = r ? > n 1 [i | 10 20 n] xs ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f 3 x ) 33 }
