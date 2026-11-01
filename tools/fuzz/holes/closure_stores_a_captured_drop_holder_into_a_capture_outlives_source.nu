// closure_stores_a_captured_drop_holder_into_a_capture_outlives_source: agora #331 — a closure assigning one captured `% Drop` holder another, which holds a view of a block's String: the String is freed at the block's end, and the outer holder's destructor reads it.
// Closed: a closure's capture or parameter that can hold a view, of any class (a view, an owner of views, a `% Drop` holder, a closure), stored whole into one of its captures stands for what it points into, which the closure cannot see (`cv_`, __clo_cap_marks, agora #331; #312's walk set it for a view only).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #331: a closure giving one Drop holder capture another that views a block's String
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ~ W w2 @ W { ( string_data b ) }
        : ( @ v ) swap \ → v { = w w2 }
        ( swap )
    }
    ^ 0
}
