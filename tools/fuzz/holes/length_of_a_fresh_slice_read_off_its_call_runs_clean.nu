// length_of_a_fresh_slice_read_off_its_call_runs_clean: `( n . ( mk ) 1 )` and `( n . ( mk ) length )`: the slice `mk` made is released after the read
// Closed (agora #925): a field read of a slice a call made releases the slice by the call's own answer once the read has what it needs: the length, a number element, or a copy of a String element on the runs the slice was the caller's (gen_member, __mb_slice_tmp_flag, __mb_slice_tmp_drop).
// main 58ab303: LeakSanitizer reported both slices never released.
// map: §7.6 | A2 | runs-clean | - | agora #925: ( n . ( mk ) 1 ) and ( n . ( mk ) length ): the slice mk made is released after the read
@ mk → [i { ^ [i | 7 8 9] }
@ main → i { ( nurl_println_int . ( mk ) 1 ) ( nurl_println_int . ( mk ) length ) ^ 0 }
