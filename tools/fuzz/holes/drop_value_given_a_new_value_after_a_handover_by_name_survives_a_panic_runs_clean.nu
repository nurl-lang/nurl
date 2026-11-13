// drop_value_given_a_new_value_after_a_handover_by_name_survives_a_panic_runs_clean: a `% Drop` struct handed over by name (`= t a`), given a new value (`= a ( mk … )`), then a panic under recover.
// Closed (agora #667): as for a String, the handover forgot `a`'s journal entry for good, and its next value leaked under recover. The entry is flag-gated, so it is kept.
// map: §7 | A2 | runs-clean | - | agora #667: a `% Drop` value given a new value after a handover by name, under a panic
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Res { String tag }

% Drop Res { @ drop Res r → v { ( nurl_println ( string_data . r tag ) ) } }

@ mk s t → Res { ^ @ Res { ( string_from t ) } }

@ work i n → i {
    : ~ Res a ( mk `resource A, long enough for the heap allocation` )
    : ~ Res t ( mk `resource T, long enough for the heap allocation` )
    = t a
    = a ( mk `resource N, long enough for the heap allocation` )
    ? == n 1 { ( panic `after the handover` ) } {}
    ^ + ( string_len . a tag ) ( string_len . t tag )
}

@ run ( @ v ) f → v { : !v PanicInfo r ( recover f ) }

@ main → i {
    ( run \ → v { : i r ( work 1 ) } )
    ( nurl_println_int ( work 0 ) )
    ^ 0
}
