// view_of_a_string_param_into_inout_outlives_source: agora #301 — an `inout` callee gives a struct of views a view of a String parameter's buffer; the String ends in a block, the view is read after it.
// Closed: a view a callee leaves an `inout` argument holding of another parameter's own buffer (`string_data src` of a String parameter) is a dependency of that argument on what the caller passed, as a view parameter stored whole is (agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: a struct of views given a view of a String parameter's buffer by an `inout` callee, read after the String ended
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( repoint w b )
    }
    ( nurl_println . w v )
    ^ 0
}
