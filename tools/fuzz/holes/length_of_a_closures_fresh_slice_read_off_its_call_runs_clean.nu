// length_of_a_closures_fresh_slice_read_off_its_call_runs_clean: `. ( g ) 1` with `g` a closure making a slice
// Closed (agora #925): a field read of a slice a call made releases the slice by the call's own answer once the read has what it needs: the length, a number element, or a copy of a String element on the runs the slice was the caller's (gen_member, __mb_slice_tmp_flag, __mb_slice_tmp_drop).
// main 58ab303: LeakSanitizer reported the slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #925: . ( g ) 1 with g a closure making a slice
@ main → i { : ( @ [i ) g \ → [i { ^ [i | 1 2] } ( nurl_println_int . ( g ) 1 ) ^ 0 }
