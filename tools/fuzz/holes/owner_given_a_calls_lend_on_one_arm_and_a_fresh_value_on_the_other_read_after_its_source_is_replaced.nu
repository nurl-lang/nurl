// owner_given_a_calls_lend_on_one_arm_and_a_fresh_value_on_the_other_read_after_its_source_is_replaced: `? c { = o ( id other ) } { = o ( mk ) }`, then `= other …` and o read: the call's arm links o to nothing (CodeRabbit on github#1915)
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader a statement before the replacement linked to it (__eng_linked; agora #886). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-886: `? c { = o ( id other ) } { = o ( mk ) }`, then `= other …` and o read: the call's arm links o to nothing (CodeRabbit on github#1915)
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : i k ( nurl_str_len `x` )
    ? == k 1 { = o ( id other ) } { = o ( string_from `dddddddddddddddddddddddddddddddd` ) }
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
