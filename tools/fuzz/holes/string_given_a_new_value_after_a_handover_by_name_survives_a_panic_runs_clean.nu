// string_given_a_new_value_after_a_handover_by_name_survives_a_panic_runs_clean: `= t a`, `= a ( string_from … )`, then a panic under recover.
// Closed (agora #667): the assignment forgot `a`'s journal entry when it handed the value to `t`, and nothing registered it again when `a` was given a new value — the unwind left that value to nobody (leak under recover). An entry the drain reads the drop flag for is kept now: the flag is the one `a`'s scope end drops by, so it says nothing is owned once the value moved on, and the new value once it is given one.
// map: §7 | A2 | runs-clean | - | agora #667: the panic journal forgot a moved-from source for good; its next value leaked under recover
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ work i n → i {
    : ~ String a ( string_from `string A, long enough for the heap allocation, yes` )
    : ~ String t ( string_from `string T, long enough for the heap allocation, yes` )
    = t a
    = a ( string_from `string N, long enough for the heap allocation, yes` )
    ? == n 1 { ( panic `after the handover` ) } {}
    ^ + ( string_len a ) ( string_len t )
}

@ run ( @ v ) f → v { : !v PanicInfo r ( recover f ) }

@ main → i {
    ( run \ → v { : i r ( work 1 ) } )
    ( nurl_println_int ( work 0 ) )
    ^ 0
}
