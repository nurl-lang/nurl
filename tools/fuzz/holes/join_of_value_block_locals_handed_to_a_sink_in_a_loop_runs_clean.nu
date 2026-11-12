// join_of_value_block_locals_handed_to_a_sink_in_a_loop_runs_clean: `: String e { : String s … : String t … ? == 0 % k 2 s t }  ( eat e )` each round of a loop: the binding the join did not select leaked
// Closed: the value block's tail binding is routed to e's drop flag (#615 / #668), so the unselected local drops at its block's end (agora #628 item 5).
// main 9052104: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #628: a join of value block locals handed to a sink leaked the other one
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ main → i { : ~ i k 0 ~ < k 3 { : String e { : String s ( string_from `first local long enough for the heap buffer` ) : String t ( string_from `second local long enough for the heap buffer` ) ? == 0 % k 2 s t } ( nurl_println_int ( eat e ) ) = k + k 1 } ^ 0 }
