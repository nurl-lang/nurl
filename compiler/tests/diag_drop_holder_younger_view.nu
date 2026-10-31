// A value whose destructor may read the views it holds is refused a view
// of a binding declared after it, where it gains the view: values are
// dropped newest first, at a scope's end and by a panic's unwind, so the
// younger binding would be freed before the destructor reads it. Refused
// even when the value is pointed back before the younger one ends — a
// panic in between would unwind both (agora #254).

$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    {
        : String b ( string_from `the inner string` )
        = w @ W { ( string_data b ) }
        = w @ W { ( string_data a ) }
    }
    ^ 0
}
