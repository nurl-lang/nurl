// owner_given_an_inout_parameter_by_name_read_after_the_parameter_is_replaced: `= o p` of an `inout String` parameter, then `= p …` and o read: the parameter has no drop flag to hand over from, so its old value is freed under o (CodeRabbit on github#1915)
// Closed in the ownership engine: an `inout` parameter's replacement hands its old value to no reader, as codegen frees it outright (eng_handover; agora #886). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-886: `= o p` of an `inout String` parameter, then `= p …` and o read: the parameter has no drop flag to hand over from, so its old value is freed under o (CodeRabbit on github#1915)
$ `stdlib/core/string.nu`

@ swap_in inout String p → v {
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o p
    = p ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    : ~ String w ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    ( swap_in w )
    ( nurl_println ( string_data w ) )
    ^ 0
}
