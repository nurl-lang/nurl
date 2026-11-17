// owner_given_a_calls_lend_then_itself_back_read_after_its_source_is_replaced: `= o ( id other )  = o ( id o )`, then `= other …` and o read: no `=` of a call links o to other, so its old value is freed under o
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader a statement before the replacement linked to it - a `:` binding or an `=` by name (__eng_linked; agora #886). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-886: `= o ( id other )  = o ( id o )`, then `= other …` and o read: no `=` of a call links o to other, so its old value is freed under o
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o ( id other )
    = o ( id o )
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
