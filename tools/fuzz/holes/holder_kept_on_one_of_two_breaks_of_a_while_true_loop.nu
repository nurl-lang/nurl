// holder_kept_on_one_of_two_breaks_of_a_while_true_loop: agora #453 guard — one `break` before the repoint, one after
// Guard: a `~ T` loop left by a `break` on a path where the holder still views the local is refused, as before (agora #453 changes only the head's exit).
// main: refused.
// map: §7.6 | A2 | rejected | - | agora #453 guard: one `break` before the repoint, one after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i j 0
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ~ T {
            = j + j 1
            ? == j 1 { break } {}
            = a @ W { `lit` }
            ? > j 2 { break } {}
        }
    }
    ( nurl_println . a v )
    ^ 0
}
