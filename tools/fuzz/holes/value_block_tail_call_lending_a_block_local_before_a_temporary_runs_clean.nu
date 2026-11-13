// value_block_tail_call_lending_a_block_local_before_a_temporary_runs_clean: as value_block_tail_call_lending_a_temporary_past_a_block_local_runs_clean, the block local first
// Closed: mem_blk_tail_copy_slot copies the block's value in place only where the tail call did not already copy its result (__call_copied_own): copied twice, the call's copy was overwritten and leaked (agora #822).
// main 44a5e0c: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #822: the arguments the other way round
$ `stdlib/core/string.nu`

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ id String a → String { ^ a }

@ main → i { : ~ i k 0 ~ < k 3 { : String g { : String s ( string_from `s long enough for the heap buffer` ) ( pick s ( string_concat ( string_clone s ) ( string_clone s ) ) ) } ( nurl_println_int ( string_len g ) ) = k + k 1 } ^ 0 }
