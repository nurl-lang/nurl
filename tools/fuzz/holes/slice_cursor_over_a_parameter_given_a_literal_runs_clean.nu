// slice_cursor_over_a_parameter_given_a_literal_runs_clean: `: ~ [i r xs  = r [i | 4 5]`
// Closed: r's flag goes up with the fresh literal, and its release frees it.
// main 6e45ef9: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #664: a borrow given a fresh slice
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n [i xs → i { : ~ [i r xs = r [i | 4 5] ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f 3 x ) 9 }
