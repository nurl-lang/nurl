// holder_repointed_before_the_break_of_a_while_one_loop: agora #453 — the same with `~ 1 {`
// Accepted: a loop whose condition is the literal `T` (or `1`) is left only by its `break`s, so it leaves with their dependencies, not its head's — a holder repointed before every `break` no longer views what it viewed when the loop was entered (bck_loop, __vd_restore; agora #453).
// main: refused ("'a' holds a view of 't' … and 't' ended"); runs clean under AddressSanitizer here.
// map: §7.6 | A2 | runs-clean | - | agora #453: the same with `~ 1 {`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ~ 1 {
            = a @ W { `lit` }
            break
        }
    }
    ( nurl_println . a v )
    ^ 0
}
