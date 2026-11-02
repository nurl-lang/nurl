// view_param_kept_in_a_second_inout_holder: agora #370 — a callee stores its view parameter into its SECOND inout holder; the caller reads that holder after the view's source ended
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a callee stores its view parameter into its SECOND inout holder; the caller reads that holder after the view's source ended
$ `stdlib/core/string.nu`

: W { s v }

@ second inout W first inout W other s src → v { = other @ W { src } }

@ main → i {
    : ~ W a @ W { `a literal` }
    : ~ W b @ W { `b literal` }
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( second a b ( string_data s ) )
    }
    ( nurl_println . b v )
    ^ 0
}
