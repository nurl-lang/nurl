// value_block_tail_call_lending_a_temporary_past_a_block_local_runs_clean: `: String g { : String s … ( pick ( string_concat … ) s ) }` each round: the call may lend its temporary or the block's s
// Closed: mem_blk_tail_copy_slot copies the block's value in place only where the tail call did not already copy its result (__call_copied_own): copied twice, the call's copy was overwritten and leaked (agora #822).
// main 44a5e0c: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #822: a tail call lending a temporary or a block local
$ `stdlib/core/string.nu`

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ main → i { : ~ i k 0 ~ < k 3 { : String g { : String s ( string_from `block local long enough for the heap buffer` ) ( pick ( string_concat ( string_clone s ) ( string_clone s ) ) s ) } ( nurl_println_int ( string_len g ) ) = k + k 1 } ^ 0 }
