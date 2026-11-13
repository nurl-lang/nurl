// option_of_an_option_from_a_call_given_back_runs_clean: `= o ( f o k )` over a `? ?String` bound from a call, `f` below its caller handing back its argument or a call's fresh value.
// Closed (agora #475): with a key for the nested option and a per-call answer for a function returning one (__is_hown_ty by nesting), the run that hands back o's own value keeps it and the one that hands over a fresh value releases the old one.
// map: §7.6 | A2 | runs-clean | - | agora #475: an option of an option from a call, given back by a callee below
$ `stdlib/core/string.nu`

@ mk → ?? String { ^ @ ?? String { T @ ?String { T ( string_from `the owned inner string, long enough for the heap` ) } } }

@ main → i {
    : ~ ? ? String o ( mk )
    = o ( f o 1 )
    = o ( f o 0 )
    ^ 0
}

@ f ? ? String o i k → ?? String {
    ? == k 1 { ^ o } {}
    ^ ( mk )
}
