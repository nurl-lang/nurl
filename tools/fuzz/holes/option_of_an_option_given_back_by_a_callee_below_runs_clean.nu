// option_of_an_option_given_back_by_a_callee_below_runs_clean: `= o ( f o k )` over a `? ?String`, with `f` defined below its caller, handing back its argument on one run and a fresh nested literal on another.
// Closed (agora #475): an option's payload that is an option itself has blanks in its LLVM spelling, which __wrap_part declines, so the nested option had no key and the keep rule released o's value while the new one still was it (heap-use-after-free). Its key is its innermost payload's now (__wrap_part_key, mem_ud_ident_key by nesting).
// map: §7.6 | A2 | runs-clean | - | agora #475: the keep rule for an option of an option
$ `stdlib/core/string.nu`

@ show ? ? String o → v { ?? o { T i → { ?? i { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `inner none` ) } } } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? ? String o @ ??String { T @ ?String { T ( string_from `the owned inner string, long enough for the heap` ) } }
    = o ( f o 1 )
    ( show o )
    = o ( f o 0 )
    ( show o )
    = o ( f o 1 )
    ( show o )
    ^ 0
}

@ f ? ? String o i k → ??String {
    ? == k 1 { ^ o } {}
    ^ @ ??String { T @ ?String { T ( string_from `a fresh inner string, long enough for the heap` ) } }
}
