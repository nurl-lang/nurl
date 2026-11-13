// slice_owner_given_a_parameter_on_one_path_runs_clean: as slice_owner_given_a_parameter_runs_clean, on one path only
// Closed: the same, by the flag on that path.
// main 6e45ef9: AddressSanitizer: attempting double-free.
// map: §7.6 | A2 | runs-clean | - | agora #664: on one path
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n [i xs → i { : ~ [i r [i | 0] ? > n 1 { = r xs } {} ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f 3 x ) 3 }
