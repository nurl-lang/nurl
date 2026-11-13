// slice_bound_again_by_name_and_handed_back_runs_clean: `: [i c a  : [i d c  ^ d` out of a local slice literal
// Closed: `: [i c a` out of an owned slice is a move, as `= dst src` is: c owns the buffer, a's slot is emptied (__slice_let_moves).
// main 6e45ef9: AddressSanitizer: heap-use-after-free (the caller read what a released).
// map: §7.6 | A2 | runs-clean | - | agora #664: a second name
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n → [i { : [i a [i | 1 n] : [i c a : [i d c ^ d }
@ main → i { : [i r ( f 3 ) ^ - ( sum r ) 4 }
