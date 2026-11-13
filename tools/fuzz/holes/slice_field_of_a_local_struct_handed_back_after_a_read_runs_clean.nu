// slice_field_of_a_local_struct_handed_back_after_a_read_runs_clean: as slice_field_of_a_local_struct_handed_back_runs_clean, another field read first
// Closed: the field is taken.
// main 6e45ef9: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #664: after a read of another field
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ eat sink [i xs → i { ^ ( sum xs ) }
: Q { [i xs i n }
@ f i n → [i { : Q q @ Q { [i | 1 n] n } : i m . q n ^ . q xs }
@ main → i { : [i r ( f 2 ) ^ - ( sum r ) 3 }
