// function_hands_a_clearing_callee_a_field_of_its_parameters_element: agora #461 — `( clr . ( vec_at [H] hs 0 ) rows )` in `top`
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function hands a clearing callee a field of its parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: H { ( Vec String ) rows }

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec H ) hs → v {
    ( clr . ( vec_at [H] hs 0 ) rows )
}

@ main → i {
    : ( Vec H ) hs ( vec_new [H] )
    : ( Vec String ) rs ( vec_new [String] )
    ( vec_push [String] rs ( string_from `a string long enough to live on the heap for sure` ) )
    ( vec_push [H] hs @ H { rs } )
    : H h ( vec_at [H] hs 0 )
    : s d ( string_data ( vec_at [String] . h rows 0 ) )
    ( top hs )
    ( nurl_println d )
    ^ 0
}
