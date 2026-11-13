// slice_field_of_a_local_struct_handed_back_runs_clean: `: Q q @ Q { [i | 1 2 n] n }  ^ . q xs`
// Closed: a slice field of a local struct handed back is taken: the field is emptied, so the struct's release frees nothing of it, and the caller owns it.
// main 6e45ef9: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #664: a returned field
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
: Q { [i xs i n }
@ f i n → [i { : Q q @ Q { [i | 1 2 n] n } ^ . q xs }
@ main → i { : [i r ( f 3 ) ^ - ( sum r ) 6 }
