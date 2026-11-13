// slice_literal_handed_back_reading_a_local_slice_runs_clean: `: [i a [i | 1 n 3 4 5]  ^ [i | ( sum a ) 6]`
// Closed: a returned slice literal is a fresh buffer: it skips no local's release as the last name read.
// main 6e45ef9: LeakSanitizer (strict): detected memory leaks (a).
// map: §7.6 | A2 | runs-clean | - | agora #664: a returned literal
@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }
@ f i n → [i { : [i a [i | 1 n 3 4 5] ^ [i | ( sum a ) 6] }
@ main → i { : [i r ( f 3 ) ^ - ( sum r ) 22 }
