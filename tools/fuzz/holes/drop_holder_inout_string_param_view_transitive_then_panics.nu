// drop_holder_inout_string_param_view_transitive_then_panics: agora #301 — #284's transitive shape through a callee that takes the String: `mid` passes its `inout` `% Drop` holder on to `repoint` with its own local String, then panics before pointing it back.
// Closed: a view a callee leaves an `inout` argument holding of another parameter's own buffer (`string_data src` of a String parameter) is a dependency of that argument on what the caller passed, as a view parameter stored whole is (agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free (nurl__jrnl_drain).
// map: §2.14 | A2 | rejected | - | agora #301: an inout Drop holder handed on with a callee local's String, viewed by the inner callee, then a panic
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ mid inout W w i k → v {
    : String b ( string_from `the callee's own string, freed by the unwind before the holder's destructor reads it` )
    ( repoint w b )
    ? > k 2 { ( panic `unwind` ) } {}
    = w @ W { `literal again` }
}

@ f i k → v {
    : ~ W w @ W { `literal` }
    ( mid w k )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 3 ) } )
    ( puts `ran` )
    ^ 0
}
