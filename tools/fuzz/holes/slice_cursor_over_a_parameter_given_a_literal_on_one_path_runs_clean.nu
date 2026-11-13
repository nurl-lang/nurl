// slice_cursor_over_a_parameter_given_a_literal_on_one_path_runs_clean: as slice_cursor_over_a_parameter_given_a_literal_runs_clean, on one path
// Closed: the same, by the flag.
// main 6e45ef9: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #664: on one path
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ eat sink [i xs → i { ^ ( sum xs ) }
@ f [i xs → i { : ~ [i r xs ? > ( sum xs ) 2 { = r [i | 9] } {} ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f x ) 9 }
