// closure_local_bound_from_a_view_capture_stored_into_a_capture: a local bound from a captured view, stored into another capture.
// Closed: inside a closure body, a view bound from a capture or a parameter of the closure that the walk cannot see into (`cv_`) is one too, so storing that local into a capture or the closure's `inout` parameter is refused as storing the source itself is (agora #332).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #332: a local bound from a captured view, stored into another capture
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : ~ V w @ V { `lit` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        : s bv ( string_data b )
        : ( @ v ) setw \ → v { : s t bv = w @ V { t } }
        ( setw )
    }
    ( nurl_println . w v )
    ^ 0
}
