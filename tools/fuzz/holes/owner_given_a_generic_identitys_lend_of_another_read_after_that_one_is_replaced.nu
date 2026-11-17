// owner_given_a_generic_identitys_lend_of_another_read_after_that_one_is_replaced: `= o ( same [String] other )`, then `= other …` and o read
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader codegen links - not to one `=` gave a call's lend (__eng_call_lent_reader; agora #881). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-881: `= o ( same [String] other )`, then `= other …` and o read
$ `stdlib/core/string.nu`

@ same [T] T a → T { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o ( same [String] other )
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
