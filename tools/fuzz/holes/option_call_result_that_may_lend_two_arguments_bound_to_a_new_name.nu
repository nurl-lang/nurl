// option_call_result_that_may_lend_two_arguments_bound_to_a_new_name: agora #412 — guard: : ?String r ( pick o other 1 ), o left as it was
// Runs clean: what the refusal's message advises — a copy of the result, or the result under a new name — owns or views without ambiguity (agora #412).
// main: ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #412: guard: : ?String r ( pick o other 1 ), o left as it was
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ?String other @ ?String { T ( string_from `another value long enough for the heap` ) }
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    : ?String r ( pick o other 1 )
    ?? r { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
