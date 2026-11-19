// string_element_of_a_fresh_slice_read_off_its_call_runs_clean: `: String e . ( mks ) k` and `( string_len . ( mks ) k )`: a String element read out of a `[String` a call made
// Closed (agora #925): a field read of a slice a call made releases the slice by the call's own answer once the read has what it needs: the length, a number element, or a copy of a String element on the runs the slice was the caller's (gen_member, __mb_slice_tmp_flag, __mb_slice_tmp_drop).
// main 58ab303: LeakSanitizer reported both slices and their Strings never released.
// map: §7.6 | A2 | runs-clean | - | agora #925: : String e . ( mks ) k and ( string_len . ( mks ) k ): a String element read out of a [String a call made
$ `stdlib/core/string.nu`

@ mks → [String { ^ [String | ( string_from `a` ) ( string_from `bc` )] }
@ main → i {
    : i k 1
    : String e . ( mks ) k
    ( nurl_println_int ( string_len e ) )
    ( nurl_println_int ( string_len . ( mks ) k ) )
    ^ 0
}
