// slice_owner_given_a_parameter_runs_clean: `: ~ [i r [i | 0]  = r xs`, xs a parameter
// Closed: r's drop flag goes down when it is given a borrow: its old value is released, the caller's xs is not.
// main 6e45ef9: AddressSanitizer: attempting double-free (r released the caller's slice).
// map: §7.6 | A2 | runs-clean | - | agora #664: an owner given a borrow
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f [i xs → i { : ~ [i r [i | 0] = r xs ^ ( sum r ) }
@ main → i { : [i x [i | 1 2] ^ - ( f x ) 3 }
