// holder_kept_by_a_break_after_its_dependency_cleared_later_in_the_loop: agora #389 — a holder given a view in a loop body, the loop left by a break before the body gives the holder a new value
// Closed: a break (and a continue) records the dependencies it leaves with, joined back where the loop is left (or at its head): __vd_snapshot / __vd_join.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #389: a holder given a view in a loop body, the loop left by a break before the body gives the holder a new value
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 1
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ~ i j 0
        ~ < j 3 {
            ( k a t )
            ? == j n { break } {}
            = a @ W { `lit` }
            = j + j 1
        }
    }
    ( nurl_println . a v )
    ^ 0
}
