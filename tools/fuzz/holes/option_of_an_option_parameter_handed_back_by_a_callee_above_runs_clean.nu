// option_of_an_option_parameter_handed_back_by_a_callee_above_runs_clean: `= o ( f o k )` over a `? ?String`, with `f` defined above its caller, returning its parameter `o` on one run and a fresh nested literal on another.
// Closed (agora #475): an option of an option has no copy, and `__is_hown_ty` answered "owns nothing" for every type with no copy that is no `% Drop` value — so `f` answered no call, its `^ o` path read as "owned" statically, and the caller kept o's old value back on the run that handed over a fresh one (a leak). A wrap with no copy is asked by what its sides own now: `f` answers per call, the parameter's run by its flag.
// map: §7.6 | A2 | runs-clean | - | agora #475: an option of an option handed back as a parameter by a callee above
$ `stdlib/core/string.nu`

@ f ? ? String o i k → ?? String {
    ? == k 1 { ^ o } {}
    ^ @ ?? String { T @ ?String { T ( string_from `a fresh inner string, long enough for the heap` ) } }
}

@ show ? ? String o → v { ?? o { T i → { ?? i { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `inner none` ) } } } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? ? String o @ ?? String { T @ ?String { T ( string_from `the owned inner string, long enough for the heap` ) } }
    = o ( f o 1 )
    ( show o )
    = o ( f o 0 )
    ( show o )
    = o ( f o 1 )
    ( show o )
    ^ 0
}
