// function_stores_a_local_copy_of_its_view_parameter_into_an_inout_holder: a function copies its view parameter into a local and stores it into an inout struct, read after the caller's String is gone.
// Closed: a local copy of a view parameter (`: s t p`) stored into a holder keeps that parameter, as the parameter stored by name does (agora #346).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #346: a function copies its view parameter into a local and stores it into an inout struct, read after the caller's String is gone
$ `stdlib/core/string.nu`

: V { s v }

@ setw inout V w s p → v {
    : s t p
    = w @ V { t }
}

@ main → i {
    : ~ V w @ V { `lit` }
    {
        : String b ( string_from `a block-local string, freed at its end, long enough` )
        ( setw w ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
