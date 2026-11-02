// option_owner_given_a_copy_of_a_call_that_may_lend_itself_own_run: agora #412 — guard: = o ( mem_dup ( pick o other 0 ) )
// Runs clean: what the refusal's message advises — a copy of the result, or the result under a new name — owns or views without ambiguity (agora #412).
// main: ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #412: guard: = o ( mem_dup ( pick o other 0 ) )
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ?String other @ ?String { T ( string_from `another value long enough for the heap` ) }
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( mem_dup ( pick o other 0 ) )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
