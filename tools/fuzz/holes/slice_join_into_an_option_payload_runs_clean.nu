// slice_join_into_an_option_payload_runs_clean: `@ ?[i { T ? > c 0 ( mk ) a }` (the fresh arm taken) and `@ ?[i { T ? > c 5 ( mk ) a }` (the binding lent): a slice join stored into an option's slice payload
// Closed (agora #903): an option owns its slice payload as a struct its slice field (#841), and a join stored there is copied on the runs it lent only (`__slice_join_lent`): the fresh arm's slice is the option's.
// main aae76ca: LeakSanitizer: the fresh arm's slice leaked.
// map: §7.6 | A2 | runs-clean | - | agora #903: a slice join stored into an option's slice payload, the fresh arm taken and the binding lent
@ mk → [i { ^ [i | 1 2 3] }

@ main → i {
    : [i a [i | 4 5]
    : i c 1
    : ?[i o ? > c 0 @ ?[i { T ? > c 0 ( mk ) a } @ ?[i { F }
    : ?[i p @ ?[i { T ? > c 5 ( mk ) a }
    ?? o { T s → { ~ x s { ( nurl_println_int x ) } } F → {} }
    ?? p { T s → { ~ x s { ( nurl_println_int x ) } } F → {} }
    ~ x a { ( nurl_println_int x ) }
    ^ 0
}
