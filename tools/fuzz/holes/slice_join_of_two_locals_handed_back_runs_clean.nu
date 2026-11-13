// slice_join_of_two_locals_handed_back_runs_clean: `^ ? > n 0 a b` over two local slices
// Closed: a returned join of own slices is the caller's: the return frees each local only where its buffer is not the one handed back, by identity (mem_emit_slice_free_unless).
// main 6e45ef9: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #664: a returned join
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n → [i { : [i a [i | 1 n] : [i b [i | 2 n] ^ ? > n 0 a b }
@ main → i { : [i r ( f 3 ) ^ - ( sum r ) 4 }
