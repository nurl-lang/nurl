// closure_assigned_a_value_block_under_a_defer_calling_it_runs_clean: the guard — `= a { : ( @ i i ) h \ … h }` while a `;` defer that calls `a` is armed, every capture a binding of the enclosing scope: runs clean.
// map: §7.6 | A2 | runs-clean | - | guard: `= a { : ( @ i i ) h \ … h }` while a `;` defer that calls `a` is armed (agora #846)
$ `stdlib/core/string.nu`

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    ; { ( nurl_println_int ( a 1 ) ) }
    = a { : ( @ i i ) h \ i x → i { ^ + + x 2 ( string_len tag ) } h }
    ( nurl_println_int ( a 1 ) )
    ^ 0
}
