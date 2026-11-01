// closure_stores_a_captured_struct_with_a_view_field_into_a_capture_outlives_source: agora #331 — a closure assigning one captured struct, with an owned field and a view field, another whose view is of a block's String: the String is freed at the block's end and the outer struct still points into it.
// Closed: a closure's capture or parameter that can hold a view, of any class (a view, an owner of views, a `% Drop` holder, a closure), stored whole into one of its captures stands for what it points into, which the closure cannot see (`cv_`, __clo_cap_marks, agora #331; #312's walk set it for a view only).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #331: a closure giving one capture another capture with an owned and a view field
$ `stdlib/core/string.nu`

: S { s v String name }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ S w @ S { ( string_data a ) ( string_from `outer` ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ~ S w2 @ S { ( string_data b ) ( string_from `inner` ) }
        : ( @ v ) swap \ → v { = w w2 }
        ( swap )
    }
    ( nurl_println . w v )
    ^ 0
}
