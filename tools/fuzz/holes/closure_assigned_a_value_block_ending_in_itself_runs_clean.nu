// closure_assigned_a_value_block_ending_in_itself_runs_clean: `: ~ ( @ i i ) a \\ … tag …  = a { : i z ( a 1 ) a }` then `( a 1 )`
// Closed: `= a { … a }`, a closure whose tail is the target itself, is `= a a`: nothing is taken over or released (agora #638).
// main 006aa3e: AddressSanitizer: heap-use-after-free (a's env released as the old value and stored back).
// map: §7.6 | A2 | runs-clean | - | agora #638: a closure target as its own block's tail
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ main → i {
    : String tag ( string_from `tag string long enough for a heap buffer` )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    = a { : i z ( a 1 ) a }
    ( nurl_println_int ( a 1 ) )
    ^ 0
}
