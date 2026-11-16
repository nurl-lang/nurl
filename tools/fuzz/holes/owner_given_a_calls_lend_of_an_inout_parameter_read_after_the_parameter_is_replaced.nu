// owner_given_a_calls_lend_of_an_inout_parameter_read_after_the_parameter_is_replaced: `= o ( id p )` of an `inout String` parameter, then `= p …` and o read
// Closed in the ownership engine: an `inout` parameter's replacement hands its old value to no reader, as codegen frees it outright (eng_handover; agora #886). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-886: `= o ( id p )` of an `inout String` parameter, then `= p …` and o read
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ swap_in inout String p → v {
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o ( id p )
    = p ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    : ~ String w ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    ( swap_in w )
    ( nurl_println ( string_data w ) )
    ^ 0
}
