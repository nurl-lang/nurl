// drop_holder_given_a_string_param_view_through_inout: agora #301 — a `% Drop` holder given a view of a younger String's buffer by an `inout` callee that takes the String itself; the destructor reads it after the String ended.
// Closed: a view a callee leaves an `inout` argument holding of another parameter's own buffer (`string_data src` of a String parameter) is a dependency of that argument on what the caller passed, as a view parameter stored whole is (agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #301: a `% Drop` holder given a view of a younger String's buffer by an `inout` callee taking the String
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( repoint w b )
    }
    ^ 0
}
