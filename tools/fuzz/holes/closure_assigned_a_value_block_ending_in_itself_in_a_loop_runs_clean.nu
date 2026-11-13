// closure_assigned_a_value_block_ending_in_itself_in_a_loop_runs_clean: as closure_assigned_a_value_block_ending_in_itself_runs_clean, in a loop body
// Closed: `= a { … a }`, a closure whose tail is the target itself, is `= a a`: nothing is taken over or released (agora #638).
// main 006aa3e: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #638: the same in a loop
$ `stdlib/core/string.nu`

@ main → i { : String tag ( string_from `tag long enough for a heap buffer` ) : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) } : ~ i k 0 ~ < k 2 { = a { : i z ( a 1 ) a } = k + k 1 } ( nurl_println_int ( a 1 ) ) ^ 0 }
