// inout_target_given_a_value_block_ending_in_a_call_runs_clean: `@ set inout String p String o → v { = p { ( string_concat o o ) } }` called twice: the caller's old value and one result leaked (the direct `= p ( string_concat o o )` was clean)
// (Run with LSAN_OPTIONS=use_stacks=0:use_registers=0 to see the leak on main.)
// Closed: gen_assign's inout handle path asks the value block's tail call (rhs_eff_tt), as for the call itself (agora #628 item 3).
// main 9052104: LeakSanitizer (strict): detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #628: an inout target given a value block ending in a call leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ set inout String p String o → v { = p { ( string_concat o o ) } }

@ main → i { : ~ String t ( string_from `start string long enough for the heap buf` ) : String o ( string_from `other string long enough for the heap buf` ) ( set t o ) ( set t o ) ( nurl_println_int ( string_len t ) ) ^ 0 }
