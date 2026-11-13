// slice_join_of_three_locals_handed_back_runs_clean: as slice_join_of_two_locals_handed_back_runs_clean, three locals, a nested join
// Closed: the same, by identity.
// main 6e45ef9: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #664: a three-way returned join
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ eat sink [i xs → i { ^ ( sum xs ) }
@ f i n → [i { : [i a [i | 1 n] : [i b [i | 2 n] : [i c [i | 3 n] ^ ? == n 0 a ? == n 1 b c }
@ main → i { : [i r ( f 1 ) ^ - ( sum r ) 3 }
