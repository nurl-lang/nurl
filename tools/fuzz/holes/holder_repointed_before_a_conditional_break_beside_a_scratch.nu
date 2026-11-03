// holder_repointed_before_a_conditional_break_beside_a_scratch: agora #453 — the same beside a scratch String (the task's example)
// Accepted: a loop whose condition is the literal `T` (or `1`) is left only by its `break`s, so it leaves with their dependencies, not its head's — a holder repointed before every `break` no longer views what it viewed when the loop was entered (bck_loop, __vd_restore; agora #453).
// main: refused ("'a' holds a view of 't' … and 't' ended"); runs clean under AddressSanitizer here.
// map: §7.6 | A2 | runs-clean | - | agora #453: the same beside a scratch String (the task's example)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ f → i {
    : ~ W a @ W { `x` }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        : ~ String x ( string_from `a scratch string that the loop frees` )
        ~ T {
            = x ( string_from `the scratch string given again` )
            ( string_free x )
            = a @ W { `lit` }
            ? T { break } {}
        }
    }
    ( nurl_println . a v )
    ^ 0
}

@ main → i { ^ ( f ) }
