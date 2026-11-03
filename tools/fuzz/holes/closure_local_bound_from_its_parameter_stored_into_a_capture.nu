// closure_local_bound_from_its_parameter_stored_into_a_capture: `: s t p` of the closure's view parameter, then `= w @ V { t }` into a capture.
// Closed: inside a closure body, a view bound from a capture or a parameter of the closure that the walk cannot see into (`cv_`) is one too, so storing that local into a capture or the closure's `inout` parameter is refused as storing the source itself is (agora #332).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #332: `: s t p` of the closure's view parameter, then `= w @ V { t }` into a capture
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : ~ V w @ V { `lit` }
    : ( @ v s ) setw \ s p → v { : s t p = w @ V { t } }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        ( setw ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
