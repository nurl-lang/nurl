// fields_of_a_lent_slice_read_off_its_call_runs_clean: `. ( id t ) 1`, `. ( ids ts ) k` and `. ( pick t c ) 1`: a slice a call lent is read and left to its owner, one it made is released
// Closed (agora #925): a field read of a slice a call made releases the slice by the call's own answer once the read has what it needs: the length, a number element, or a copy of a String element on the runs the slice was the caller's (gen_member, __mb_slice_tmp_flag, __mb_slice_tmp_drop).
// main 58ab303: LeakSanitizer reported the slice `pick` made never released; the lent ones are their owners' (the shape the fix must keep).
// map: §7.6 | A2 | runs-clean | - | agora #925: . ( id t ) 1, . ( ids ts ) k and . ( pick t c ) 1: a slice a call lent is read and left to its owner, one it made is released
$ `stdlib/core/string.nu`

@ id [i a → [i { ^ a }
@ ids [String a → [String { ^ a }
@ pick [i a b c → [i { ? c { ^ a } {} ^ [i | 1 2 3 4] }
@ main → i {
    : [i t [i | 4 5 6]
    : [String ts [String | ( string_from `xy` ) ( string_from `z` )]
    : i k 1
    : i z 0
    ( nurl_println_int . ( id t ) 1 )
    ( nurl_println_int . ( id t ) k )
    ( nurl_println_int ( string_len . ( ids ts ) k ) )
    : String e . ( ids ts ) z
    ( nurl_println_int ( string_len e ) )
    ( nurl_println_int . ( pick t T ) 1 )
    ( nurl_println_int . ( pick t F ) 1 )
    ( nurl_println_int . t 1 )
    ( nurl_println_int ( string_len . ts z ) )
    ^ 0
}
